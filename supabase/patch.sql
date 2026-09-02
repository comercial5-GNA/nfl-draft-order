-- PATCH v1: segurança do timer, alternativas embaralhadas, ordem teste->válida,
-- ranking bloqueado até todos concluírem e correção do pgcrypto.

create extension if not exists pgcrypto with schema extensions;

alter table public.attempts
  add column if not exists option_orders jsonb not null default '{}'::jsonb;

create or replace function public.quiz_login(p_name text, p_pin text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare p participants;
begin
  select * into p from participants where name = p_name;
  if p.id is null or crypt(p_pin, p.pin_hash) <> p.pin_hash then
    raise exception 'Nome ou PIN inválido';
  end if;
  return jsonb_build_object(
    'participant_id', p.id,
    'name', p.name,
    'practice_used', p.practice_started_at is not null,
    'practice_finished', p.practice_finished_at is not null,
    'valid_used', p.valid_started_at is not null,
    'valid_finished', p.valid_finished_at is not null
  );
end $$;

create or replace function public.quiz_start(p_name text, p_pin text, p_mode text)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  p participants;
  ids integer[];
  a attempts;
  exclude_ids integer[] := '{}';
  orders jsonb := '{}'::jsonb;
  qid integer;
  perm jsonb;
begin
  if p_mode not in ('practice','valid') then raise exception 'Modo inválido'; end if;

  select * into p from participants where name = p_name for update;
  if p.id is null or crypt(p_pin, p.pin_hash) <> p.pin_hash then
    raise exception 'Nome ou PIN inválido';
  end if;

  if p_mode='practice' and p.practice_started_at is not null then
    raise exception 'Teste já utilizado';
  end if;
  if p_mode='valid' and p.valid_started_at is not null then
    raise exception 'Tentativa válida já utilizada';
  end if;
  if p_mode='valid' and p.practice_started_at is null then
    raise exception 'Inicie o teste antes da tentativa válida';
  end if;

  if p_mode='valid' then
    select coalesce(question_ids,'{}') into exclude_ids
    from attempts where participant_id=p.id and mode='practice';
  end if;

  select array_agg(id) into ids from (
    (select id from questions where difficulty='easy' and not (id=any(exclude_ids)) order by random() limit 10)
    union all
    (select id from questions where difficulty='medium' and not (id=any(exclude_ids)) order by random() limit 10)
    union all
    (select id from questions where difficulty='hard' and not (id=any(exclude_ids)) order by random() limit 10)
  ) s;

  if array_length(ids,1) <> 30 then raise exception 'Banco de perguntas insuficiente'; end if;

  foreach qid in array ids loop
    select jsonb_agg(x order by r) into perm
    from (select x, random() r from generate_series(0,3) x) s;
    orders := orders || jsonb_build_object(qid::text, perm);
  end loop;

  insert into attempts(participant_id,mode,question_ids,current_question_started_at,option_orders)
  values(p.id,p_mode,ids,null,orders) returning * into a;

  if p_mode='practice' then
    update participants set practice_started_at=now() where id=p.id;
  else
    update participants set valid_started_at=now() where id=p.id;
  end if;

  return jsonb_build_object('token',a.token,'mode',a.mode,'total',30);
end $$;

create or replace function public.quiz_question(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  a attempts;
  q questions;
  qid integer;
  ord jsonb;
  shown_options jsonb;
  started timestamptz;
  remaining integer;
begin
  select * into a from attempts where token=p_token for update;
  if a.id is null then raise exception 'Tentativa inválida'; end if;
  if a.finished_at is not null or a.current_index >= 30 then
    return jsonb_build_object('finished',true);
  end if;

  qid := a.question_ids[a.current_index+1];
  select * into q from questions where id=qid;

  if a.current_question_started_at is null then
    started := now();
    update attempts set current_question_started_at=started where id=a.id;
  else
    started := a.current_question_started_at;
  end if;

  remaining := greatest(0, 7000 - floor(extract(epoch from (now()-started))*1000)::integer);
  ord := a.option_orders -> qid::text;

  select jsonb_agg(q.options -> (v::integer) order by pos)
  into shown_options
  from jsonb_array_elements_text(ord) with ordinality t(v,pos);

  return jsonb_build_object(
    'finished',false,
    'number',a.current_index+1,
    'total',30,
    'difficulty',q.difficulty,
    'question',q.question,
    'options',shown_options,
    'remaining_ms',remaining
  );
end $$;

create or replace function public.quiz_answer(p_token uuid, p_choice integer)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  a attempts;
  q questions;
  qid integer;
  ms integer;
  ok boolean;
  weight numeric;
  original_choice integer;
begin
  select * into a from attempts where token=p_token for update;
  if a.id is null or a.finished_at is not null then raise exception 'Tentativa encerrada'; end if;
  if a.current_question_started_at is null then raise exception 'Pergunta ainda não iniciada'; end if;

  qid := a.question_ids[a.current_index+1];
  select * into q from questions where id=qid;

  ms := greatest(0, floor(extract(epoch from (now()-a.current_question_started_at))*1000)::integer);
  if ms > 7500 then p_choice := null; end if;

  if p_choice is not null and p_choice between 0 and 3 then
    original_choice := ((a.option_orders -> qid::text) ->> p_choice)::integer;
  else
    original_choice := null;
  end if;

  ok := (original_choice is not null and original_choice=q.answer);
  weight := case q.difficulty when 'easy' then 1 when 'medium' then 1.5 else 2 end;

  insert into answers(attempt_id,question_id,choice,correct,elapsed_ms)
  values(a.id,qid,p_choice,ok,least(ms,7000));

  update attempts set
    current_index=current_index+1,
    current_question_started_at=null,
    score=score + case when ok then weight else 0 end,
    correct_count=correct_count + case when ok then 1 else 0 end,
    correct_time_ms=correct_time_ms + case when ok then least(ms,7000) else 0 end
  where id=a.id;

  if a.current_index+1 >= 30 then
    update attempts set finished_at=now(), current_question_started_at=null where id=a.id;
    if a.mode='practice' then
      update participants set practice_finished_at=now() where id=a.participant_id;
    else
      update participants set valid_finished_at=now() where id=a.participant_id;
    end if;
    return jsonb_build_object('finished',true);
  end if;

  return jsonb_build_object('finished',false);
end $$;

-- Retorna apenas o número que falta enquanto o ranking estiver bloqueado.
-- Quando todos concluírem a válida, retorna a classificação completa.
create or replace function public.quiz_ranking()
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  total_players integer;
  finished_players integer;
  missing integer;
  rows jsonb;
begin
  select count(*) into total_players from participants;
  select count(*) into finished_players
  from attempts where mode='valid' and finished_at is not null;

  missing := greatest(0,total_players-finished_players);

  if missing > 0 then
    return jsonb_build_object('published',false,'missing',missing,'total',total_players);
  end if;

  select coalesce(jsonb_agg(to_jsonb(r) order by r.place),'[]'::jsonb)
  into rows
  from (
    select row_number() over(order by a.score desc, a.correct_time_ms asc) as place,
           p.name,a.score,a.correct_count
    from attempts a
    join participants p on p.id=a.participant_id
    where a.mode='valid' and a.finished_at is not null
  ) r;

  return jsonb_build_object('published',true,'missing',0,'total',total_players,'ranking',rows);
end $$;

grant execute on function public.quiz_login(text,text) to anon, authenticated;
grant execute on function public.quiz_start(text,text,text) to anon, authenticated;
grant execute on function public.quiz_question(uuid) to anon, authenticated;
grant execute on function public.quiz_answer(uuid,integer) to anon, authenticated;
grant execute on function public.quiz_ranking() to anon, authenticated;

notify pgrst, 'reload schema';
-- PATCH FINAL: resultado individual detalhado somente após a tentativa válida.
-- Não altera ranking, perguntas, tentativas anteriores ou PINs.

create or replace function public.quiz_result(p_token uuid)
returns jsonb
language plpgsql security definer set search_path = public, extensions
as $$
declare
  a attempts;
  p participants;
  q questions;
  ans answers;
  qid integer;
  ord jsonb;
  shown_options jsonb;
  correct_displayed integer;
  i integer;
  weight numeric;
  review jsonb := '[]'::jsonb;
begin
  select * into a from attempts where token = p_token;
  if a.id is null then raise exception 'Tentativa inválida'; end if;
  if a.mode <> 'valid' then raise exception 'Resultado detalhado disponível apenas para a tentativa válida'; end if;
  if a.finished_at is null then raise exception 'Tentativa ainda não concluída'; end if;

  select * into p from participants where id = a.participant_id;

  for i in 1..array_length(a.question_ids, 1) loop
    qid := a.question_ids[i];
    select * into q from questions where id = qid;
    select * into ans from answers where attempt_id = a.id and question_id = qid;

    ord := a.option_orders -> qid::text;

    select jsonb_agg(q.options -> (v::integer) order by pos)
      into shown_options
    from jsonb_array_elements_text(ord) with ordinality t(v,pos);

    select (pos - 1)::integer
      into correct_displayed
    from jsonb_array_elements_text(ord) with ordinality t(v,pos)
    where v::integer = q.answer
    limit 1;

    weight := case q.difficulty when 'easy' then 1 when 'medium' then 1.5 else 2 end;

    review := review || jsonb_build_array(jsonb_build_object(
      'number', i,
      'difficulty', q.difficulty,
      'question', q.question,
      'options', shown_options,
      'chosen_index', ans.choice,
      'correct_index', correct_displayed,
      'correct', ans.correct,
      'elapsed_ms', ans.elapsed_ms,
      'points', case when ans.correct then weight else 0 end,
      'max_points', weight
    ));
  end loop;

  return jsonb_build_object(
    'name', p.name,
    'score', a.score,
    'max_score', 45,
    'correct_count', a.correct_count,
    'total', 30,
    'correct_time_ms', a.correct_time_ms,
    'review', review
  );
end $$;

grant execute on function public.quiz_result(uuid) to anon, authenticated;

notify pgrst, 'reload schema';
