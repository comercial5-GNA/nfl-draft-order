NFL Draft Order Challenge — Supabase

PARTICIPANTES
- Guilherme Diniz
- Guilherme Gomes
- Gabriel Pfeffer
- Sérgio Vidal
- Caio Morato
- Gabriel Petribu
- Vitor Dornas
- Wesley Oliveira
- Pedro Fonseca
- Daniel Lopes
- João Henrique
- Gabriel Miraglia

COMO CONFIGURAR

1) Crie um projeto gratuito no Supabase.
2) Abra SQL Editor.
3) Execute primeiro: supabase/schema.sql
4) Execute depois: supabase/seed.sql
5) No Supabase, abra Project Settings > API e copie:
   - Project URL
   - anon/public key
6) Na raiz deste projeto, copie .env.example para .env e preencha:
   VITE_SUPABASE_URL=...
   VITE_SUPABASE_ANON_KEY=...
7) Terminal:
   npm install
   npm run dev

Para publicar na Vercel:
- suba o projeto no GitHub;
- importe na Vercel;
- cadastre VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY nas Environment Variables;
- deploy.

REGRAS IMPLEMENTADAS
- nome escolhido de lista fechada;
- PIN individual;
- 1 teste e 1 válida por participante;
- tentativa é consumida ao começar;
- 30 questões por tentativa (10/10/10);
- perguntas do teste são excluídas da válida;
- 7 segundos validados também no servidor;
- gabarito não é retornado ao navegador;
- ranking considera apenas a válida;
- desempate: menor soma do tempo das respostas corretas.

ATENÇÃO
Guarde PINS-ADMIN.txt para você. Não publique esse arquivo no GitHub.

PATCH FINAL (resultado individual):
- Rode supabase/patch-result.sql no SQL Editor após o patch principal.
- Na tentativa válida, o jogador vê pontuação, acertos, tempo de desempate e revisão das 30 respostas.
- No teste, o resultado continua oculto.
- O ranking geral continua bloqueado até todos os participantes concluírem.
