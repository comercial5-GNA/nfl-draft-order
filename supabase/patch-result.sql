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
