import { createClient } from "@supabase/supabase-js";

const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
);
const app=document.querySelector("#app");
const NAMES=["Guilherme Diniz", "Guilherme Gomes", "Gabriel Pfeffer", "Sérgio Vidal", "Caio Morato", "Gabriel Petribu", "Vitor Dornas", "Wesley Oliveira", "Pedro Fonseca", "Daniel Lopes", "João Henrique", "Gabriel Miraglia"];
let session={name:"",pin:"",token:null,mode:null};
let deadline=0,timer=null,locked=false;
const ACTIVE_KEY="nfl_active_attempt_v1";

function saveActiveAttempt(){
  if(session.token && session.mode){
    localStorage.setItem(ACTIVE_KEY,JSON.stringify({name:session.name,token:session.token,mode:session.mode}));
  }
}
function clearActiveAttempt(){ localStorage.removeItem(ACTIVE_KEY); }
function getActiveAttempt(){
  try{return JSON.parse(localStorage.getItem(ACTIVE_KEY)||"null")}catch{return null}
}

const rpc=async(fn,args={})=>{
  const {data,error}=await supabase.rpc(fn,args);
  if(error) throw error;
  return data;
};
const esc=s=>String(s).replace(/[&<>"']/g,c=>({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#039;"}[c]));

function home(){
 clearInterval(timer);
 app.innerHTML=`<main class="shell"><section class="card center">
 <div class="football">🏈</div><div class="eyebrow">2026</div>
 <h1>A Nata do Fantasy 26/27 Draft Order Challenge</h1>
 <p class="lead">Selecione seu nome e informe seu PIN individual.</p>
 <select id="name"><option value="">Selecione seu nome</option>${NAMES.map(n=>`<option>${esc(n)}</option>`).join("")}</select>
 <input id="pin" inputmode="numeric" maxlength="4" placeholder="PIN de 4 dígitos">
 <button id="login">Entrar</button><div id="msg" class="msg"></div>
 <button id="rank" class="admin-link">Ver ranking</button>
 </section></main>`;
 document.querySelector("#login").onclick=login;
 document.querySelector("#rank").onclick=ranking;
}
async function login(){
 const name=document.querySelector("#name").value, pin=document.querySelector("#pin").value.trim(), msg=document.querySelector("#msg");
 if(!name||pin.length!==4){msg.textContent="Selecione seu nome e informe o PIN.";return}
 try{
   const s=await rpc("quiz_login",{p_name:name,p_pin:pin});
   session={name,pin,token:null,mode:null}; dashboard(s);
 }catch(e){msg.textContent="Nome ou PIN inválido."}
}
function dashboard(s){
 app.innerHTML=`<main class="shell"><section class="card center">
 <div class="eyebrow">JOGADOR</div><h1>${esc(session.name)}</h1>
 <p class="lead">Cada modalidade pode ser iniciada apenas uma vez. Começou, consumiu a chance.</p>
 <div class="attempts">
  <button id="practice" ${s.practice_used?"disabled":""}>${s.practice_used?"Teste já utilizado":"Fazer teste"}</button>
  <button id="valid" class="secondary" ${(s.valid_used||!s.practice_used)?"disabled":""}>${s.valid_used?"Válida já utilizada":(!s.practice_used?"Faça o teste primeiro":"Fazer tentativa válida")}</button>
 </div>
 <p class="muted">30 perguntas • 7 segundos por pergunta • teste e válida usam perguntas diferentes.</p>
 <button id="logout" class="admin-link">Sair</button>
 </section></main>`;
 if(!s.practice_used) document.querySelector("#practice").onclick=()=>confirmStart("practice");
 if(!s.valid_used && s.practice_used) document.querySelector("#valid").onclick=()=>confirmStart("valid");
 document.querySelector("#logout").onclick=home;
}
function confirmStart(mode){
 const label=mode==="practice"?"TESTE":"TENTATIVA VÁLIDA";
 app.innerHTML=`<main class="shell"><section class="card center">
 <div class="eyebrow">${label}</div><h1>Pronto para começar?</h1>
 <p class="lead">Ao clicar abaixo, sua única chance será consumida. Fechar ou atualizar a página não devolve a tentativa.</p>
 <button id="go">COMEÇAR</button><button id="back" class="admin-link">Voltar</button>
 </section></main>`;
 document.querySelector("#go").onclick=()=>start(mode);
 document.querySelector("#back").onclick=async()=>dashboard(await rpc("quiz_login",{p_name:session.name,p_pin:session.pin}));
}
async function start(mode){
 try{
  const r=await rpc("quiz_start",{p_name:session.name,p_pin:session.pin,p_mode:mode});
  session.token=r.token;session.mode=mode; saveActiveAttempt(); await loadQuestion();
 }catch(e){alert(e.message);home()}
}
async function loadQuestion(){
 try{
  const q=await rpc("quiz_question",{p_token:session.token});
  if(q.finished)return finished();
  locked=false;
  const progress=q.number/q.total*100;
  app.innerHTML=`<main class="quiz-shell"><section class="quiz-card">
   <div class="quiz-top"><div><div class="eyebrow">${q.difficulty==="easy"?"Fácil":q.difficulty==="medium"?"Média":"Difícil"}</div>
   <div class="question-count">Pergunta ${q.number} de ${q.total}</div></div><div id="timer" class="timer">7</div></div>
   <div class="progress"><div style="width:${progress}%"></div></div><h2>${esc(q.question)}</h2>
   <div class="options">${q.options.map((o,i)=>`<button class="option" data-i="${i}"><span>${String.fromCharCode(65+i)}</span>${esc(o)}</button>`).join("")}</div>
  </section></main>`;
  document.querySelectorAll(".option").forEach(b=>b.onclick=()=>answer(Number(b.dataset.i)));
  deadline=performance.now()+Math.max(0,Number(q.remaining_ms ?? 7000)); clearInterval(timer);timer=setInterval(tick,100);
  tick();
 }catch(e){alert("Erro ao carregar pergunta: "+e.message)}
}
function tick(){
 const left=Math.max(0,deadline-performance.now()), shown=Math.ceil(left/1000), el=document.querySelector("#timer");
 if(el){el.textContent=shown;el.classList.toggle("urgent",shown<=2)}
 if(left<=0)answer(null);
}
async function answer(choice){
 if(locked)return;locked=true;clearInterval(timer);
 document.querySelectorAll(".option").forEach(b=>b.disabled=true);
 try{
  const r=await rpc("quiz_answer",{p_token:session.token,p_choice:choice});
  if(r.finished)finished(); else setTimeout(loadQuestion,250);
 }catch(e){alert("Erro ao registrar resposta: "+e.message)}
}
async function finished(){
 clearInterval(timer);

 if(session.mode==="practice"){
   clearActiveAttempt();
   app.innerHTML=`<main class="shell"><section class="card center"><div class="football">🏈</div>
   <div class="eyebrow">TESTE CONCLUÍDO</div>
   <h1>Agora você já conhece a ferramenta.</h1>
   <p class="lead">O teste não entra no ranking e o resultado não é exibido.</p>
   <button id="home">Tela inicial</button></section></main>`;
   document.querySelector("#home").onclick=home;
   return;
 }

 try{
   const r=await rpc("quiz_result",{p_token:session.token});
   clearActiveAttempt();
   const time=(Number(r.correct_time_ms||0)/1000).toFixed(2).replace(".",",");
   const score=Number(r.score||0).toFixed(1).replace(".",",");
   const maxScore=Number(r.max_score||45).toFixed(1).replace(".",",");
   const review=r.review||[];

   app.innerHTML=`<main class="shell"><section class="card result-card">
    <div class="center"><div class="football">🏈</div><div class="eyebrow">TENTATIVA VÁLIDA CONCLUÍDA</div>
    <h1>Seu resultado</h1><p class="lead">Seu resultado foi registrado. O ranking geral só será publicado quando todos terminarem.</p></div>
    <div class="result-summary">
      <div><strong>${score}</strong><span>pontos de ${maxScore}</span></div>
      <div><strong>${r.correct_count}/${r.total}</strong><span>acertos</span></div>
      <div><strong>${time}s</strong><span>tempo de desempate</span></div>
    </div>
    <div class="review-title"><h2>Revisão das respostas</h2><p class="muted">O tempo de desempate soma somente o tempo das respostas corretas.</p></div>
    <div class="review-list">${review.map(item=>{
      const chosen=item.chosen_index===null||item.chosen_index===undefined?null:Number(item.chosen_index);
      const correct=Number(item.correct_index);
      const chosenText=chosen===null?"Tempo esgotado":item.options[chosen];
      const correctText=item.options[correct];
      const diff=item.difficulty==="easy"?"Fácil":item.difficulty==="medium"?"Média":"Difícil";
      const pts=Number(item.points||0).toFixed(1).replace(".",",");
      const maxPts=Number(item.max_points||0).toFixed(1).replace(".",",");
      return `<article class="review-item ${item.correct?"review-correct":"review-wrong"}">
        <div class="review-head"><span>${item.correct?"✅":"❌"} ${item.number}. ${diff}</span><strong>${pts}/${maxPts} pt</strong></div>
        <h3>${esc(item.question)}</h3>
        <p><b>Sua resposta:</b> ${chosen===null?"Tempo esgotado":`${String.fromCharCode(65+chosen)} — ${esc(chosenText)}`}</p>
        ${item.correct?"":`<p><b>Resposta correta:</b> ${String.fromCharCode(65+correct)} — ${esc(correctText)}</p>`}
      </article>`;
    }).join("")}</div>
    <button id="home">Tela inicial</button>
   </section></main>`;
   document.querySelector("#home").onclick=home;
 }catch(e){
   app.innerHTML=`<main class="shell"><section class="card center"><div class="eyebrow">TENTATIVA VÁLIDA CONCLUÍDA</div>
   <h1>Resultado registrado.</h1><p class="lead">Não consegui carregar a revisão agora, mas sua tentativa foi salva.</p>
   <button id="retry">Tentar carregar resultado</button><button id="home" class="admin-link">Tela inicial</button></section></main>`;
   document.querySelector("#retry").onclick=finished;
   document.querySelector("#home").onclick=home;
 }
}
async function ranking(){
 try{
  const result=await rpc("quiz_ranking");
  if(!result.published){
    app.innerHTML=`<main class="shell"><section class="card center"><div class="eyebrow">CLASSIFICAÇÃO</div><h1>Ranking ainda não disponível</h1>
    <p class="lead">Ainda faltam <strong>${result.missing} ${result.missing===1?"participante":"participantes"}</strong> jogarem para o ranking ser publicado.</p>
    <p class="muted">Nenhuma pontuação ou posição será exibida antes de todos concluírem a tentativa válida.</p>
    <button id="back">Voltar</button></section></main>`;
  }else{
    const list=result.ranking||[];
    app.innerHTML=`<main class="shell"><section class="card wide"><div class="eyebrow">CLASSIFICAÇÃO FINAL</div><h1>Ranking</h1>
    <div class="ranking">${list.map(r=>`<div class="rank-row"><div class="place">${r.place}º</div><div class="rank-name">${esc(r.name)}</div><div class="rank-score">${Number(r.score).toFixed(1)} pts</div><div class="rank-detail">${r.correct_count}/30</div></div>`).join("")}</div>
    <button id="back">Voltar</button></section></main>`;
  }
  document.querySelector("#back").onclick=home;
 }catch(e){alert(e.message)}
}
async function boot(){
 const active=getActiveAttempt();
 if(active?.token && active?.mode){
   session={name:active.name||"",pin:"",token:active.token,mode:active.mode};
   try{
     await loadQuestion();
     return;
   }catch(e){
     clearActiveAttempt();
   }
 }
 home();
}
boot();
