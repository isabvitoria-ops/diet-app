# Central do Paciente — como trabalhar neste projeto

Quem usa isto é a Isabela, nutricionista, não pessoa técnica. Ela pede a
mudança; quem decide o caminho técnico é você.

## Regra permanente: dizer se precisa mexer no Supabase

**Ao fim de toda alteração que ela pedir, termine a resposta dizendo se ela
precisa fazer alguma coisa no Supabase.** Sempre — inclusive quando a resposta
for "não precisa". Ela pediu isso explicitamente, porque não tem como saber
sozinha o que é código e o que é banco.

Use este formato, no fim da mensagem:

> **Precisa mexer no Supabase?** Não — já está no ar, é só recarregar
> segurando Shift.

ou

> **Precisa mexer no Supabase?** Sim, uma coisa: [o que é, e por quê].
> Cole isto no SQL Editor (New query → colar → Run):
> ```sql
> ...
> ```
> Deve voltar [o que ela tem que ver na tela para saber que deu certo].

Quando for "sim", entregue o SQL **pronto para colar**, com `returning` ou um
`select` de conferência no fim — sem isso ela não tem como saber se o comando
pegou. Foi exatamente o que falhou no `tornar-admin.sql`: rodou, alterou zero
linhas e não avisou.

### O que é código (você resolve) e o que é banco (ela roda)

| Precisa de Supabase | Não precisa |
|---|---|
| Coluna, tabela, índice, política de RLS | Tela nova, botão, texto fixo, cor |
| Função ou trigger em `supabase/migracoes/` | Corrigir defeito no app |
| Promover conta a `admin` | Qualquer coisa em `src/` |
| `Authentication → URL Configuration` | Publicar no GitHub Pages |
| SMTP próprio, limite de e-mails | |

Cadastrar paciente, alimento, equivalência, guia ou restaurante **não é
nenhum dos dois**: ela faz em `/admin` e já está no ar. Quando o pedido for
desses, diga isso em vez de alterar código.

Mudou algo em `supabase/migracoes/`? Rode `npm run instalador` para regerar
`supabase/instalar.sql`, e entregue a ela **só o trecho novo**, não o arquivo
inteiro de 900 linhas.

## Publicar

Ela não sobe arquivo. Você publica:

```bash
npm run html-pages                 # gera site-pages/index.html + 404.html
cp site-pages/*.html /home/user/metodorota/
cd /home/user/metodorota && git add -A && git commit && git push origin main
```

O repositório do site é `isabvitoria-ops/metodorota` (o código é
`isabvitoria-ops/diet-app`, branch `claude/nutrition-patient-webapp-5myhmt`).
Se não estiver anexado à sessão, use `add_repo`.

Os dois arquivos têm que subir com os nomes **exatos** `index.html` e
`404.html`. Um upload pelo navegador já virou `index (1).html` uma vez, e o
site ficou na versão antiga sem dar erro nenhum.

Depois de publicar, confirme que o deploy do Pages passou antes de dizer que
está no ar.

## O que você não consegue fazer daqui

Este ambiente bloqueia `*.supabase.co` e `isabvitoria-ops.github.io`. Então
login, convite e leitura de paciente **não dá para testar daqui** — só do lado
dela. Quando algo não bater, peça um print de
`https://isabvitoria-ops.github.io/metodorota/diagnostico`: essa tela é pública
de propósito e mostra papel, situação, acesso e se o banco respondeu.

Não diga que testou o que não testou.

## Antes de publicar

`npm test` (38), `npm run typecheck`, `npm run lint` (0 erros). O resto da
arquitetura está em `CENTRAL.md`; o manual não técnico dela é `PUBLICAR.md`.
