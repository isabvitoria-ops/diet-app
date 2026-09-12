# Central do Paciente — arquitetura e manutenção

Ferramenta de consulta do paciente (troca de alimentos, comer fora,
substituições, guias, salvos) com área administrativa da nutricionista,
autenticação e controle de validade de acesso.

Para colocar no ar pela primeira vez, veja **[PUBLICAR.md](PUBLICAR.md)**.

---

## 1. A regra que governa o sistema

> **Convite não é acesso.**
> Acesso = conta autenticada **+** paciente cadastrado e vinculado **+** não
> suspenso **+** hoje dentro do período.

Essa frase existe em **um** lugar executável: a função `tem_acesso()` em
`supabase/migracoes/0002_funcoes.sql`. Todas as políticas de leitura de
conteúdo chamam ela. O frontend não recalcula a regra — ele pergunta
(`meu_acesso()`) e obedece.

Três consequências que valem saber:

- **Expirar é automático.** "Expirado" não é um status gravado: é o resultado
  de comparar a data de fim com hoje, toda vez que alguém pergunta. Não há
  rotina diária para falhar, e não há dia em que um plano vencido continue
  aberto porque alguém esqueceu de rodar algo.
- **Esconder no frontend não protege nada.** Se o paciente vencido digitar a
  URL antiga, o banco devolve zero linhas. Os portões de tela
  (`ExigeAcesso`, `ExigeAdmin`) só existem para levar a pessoa à tela certa.
- **Vencer não apaga ninguém.** Expirar, suspender e excluir são três coisas
  diferentes, e só a última pede confirmação.

Isso não é uma promessa: são 61 verificações rodando num Postgres de verdade.
Ver a seção 7.

---

## 2. Stack

| Camada | Escolha | Por quê |
|---|---|---|
| Build | Vite | Já era do projeto |
| Interface | React 18 + TypeScript | Já era do projeto |
| Rotas | react-router-dom | Já era dependência |
| Estado | Zustand | Já era dependência |
| Banco, login, arquivos | Supabase (PostgreSQL) | Pedido do briefing; RLS resolve o controle de acesso no lugar certo |
| Hospedagem | Vercel | Pedido do briefing; publica a cada envio ao GitHub |
| Estilo | CSS puro com variáveis | Sem framework: a identidade visual inteira é um bloco de variáveis |
| Testes | `node:test` nativo + psql + Playwright | Nenhuma dependência de teste instalada |

**Nenhuma dependência nova foi adicionada** em relação ao que o projeto já
tinha. A fonte de título é servida pelo próprio app.

---

## 3. Estrutura

```
supabase/
  instalar.sql          Tudo junto, para colar no SQL Editor (GERADO)
  tornar-admin.sql      Promove a sua conta a administradora
  migracoes/
    0001_esquema.sql      tabelas e índices
    0002_funcoes.sql      tem_acesso(), situacao, gatilhos, meu_acesso()
    0003_rls.sql          as políticas de acesso
    0004_dados_iniciais.sql  dados de partida (GERADO de src/central/dados/sementes)
    0005_permissoes.sql   grants explícitos
  testes/
    00_ambiente.sql       imita o Supabase num Postgres local
    01_acesso.sql         a bateria de segurança

src/central/
  rotas.ts              todos os caminhos em um lugar

  dados/                DE ONDE VEM O DADO
    repositorio.ts        a interface, e quem escolhe a implementação
    repositorioSupabase.ts  produção
    repositorioLocal.ts     modo demonstração (sementes + navegador)
    mapeadores.ts         linha do banco ↔ objeto do app
    catalogo.ts           o catálogo em memória, carregado uma vez
    indiceBusca.ts        monta a busca global a partir do catálogo
    sementes/             OS DADOS INICIAIS — é aqui que você escreve

  utils/                AS CONTAS (lógica pura, sem tela)
    calculoTroca.ts       o motor da Troca Inteligente
    porcoes.ts            porções, frações e combinações
    medidas.ts            conversão de unidade e arredondamento
    situacao.ts           a mesma regra de validade do banco, em TypeScript
    buscaAlimentos.ts / buscaGlobal.ts / texto.ts / armazenamento.ts

  autenticacao/         CONTA E PORTÕES
    SessaoContexto.tsx    quem está usando e o que pode ver
    Protegido.tsx         ExigeSessao / ExigeAcesso / ExigeAdmin
    Entrar / DefinirSenha / RecuperarSenha / SemAcesso

  admin/                ÁREA DA NUTRICIONISTA
    Painel, Pacientes, FichaPaciente, Alimentos,
    Equivalencias, Conteudos, Configuracoes

  pages/                TELAS DO PACIENTE (uma por arquivo)
  components/           peças reutilizadas
  hooks/                favoritos, pacientes, catálogo
  types/                o contrato de todos os dados
  styles/central.css    a identidade visual inteira
```

A regra que mantém isso saudável: **tela não conhece banco, banco não conhece
tela, e conta nenhuma acontece dentro de componente.** Se um número aparece na
interface, ele veio de uma função em `utils/`.

---

## 4. O banco

### Tabelas

| Tabela | Para quê |
|---|---|
| `perfis` | Uma linha por conta autenticada. Diz quem é admin. |
| `planos` | Mensal, trimestral, semestral, anual. |
| `pacientes` | O cadastro: e-mail, plano, período, status, último acesso. |
| `convites` | Registro de cada envio de convite. |
| `historico_admin` | Cadastro, convite, ativação, renovação, suspensão, reativação. |
| `unidades` | g, ml, unidade, fatia, colher… |
| `grupos_alimentares` | Carboidratos, proteínas, vegetais livres… |
| `alimentos` | Nome, grupo, porção de referência, restrições, tags. |
| `equivalencias` | As trocas com valor próprio. |
| `conteudos` | Guias e comer fora (o formato muda dentro de `corpo`). |
| `favoritos` | O que cada paciente salvou. |
| `configuracoes` | WhatsApp, nome da Central, dias de alerta. |

### Como o paciente se liga à conta

```
auth.users (Supabase)  →  perfis  →  pacientes  →  plano + período + status
```

O e-mail é a chave de encontro. A nutricionista cadastra o paciente antes de
existir conta; quando a pessoa cria a conta, um gatilho liga as duas pontas.
Se ela criar conta sem ter sido cadastrada, fica com uma conta autenticada e
**zero** acesso — que é exatamente o comportamento desejado.

### Situações

| Situação | De onde vem |
|---|---|
| `convite_pendente` | ainda não há conta vinculada |
| `nao_iniciado` | hoje é antes da data de início |
| `ativo` | dentro do período |
| `proximo_do_vencimento` | dentro do período, faltando ≤ 15 dias (configurável) |
| `expirado` | hoje é depois da data de fim |
| `suspenso` | decisão manual da nutricionista |

Só `convite_pendente`, `ativo` e `suspenso` são gravados. As outras três são
calculadas na hora, no fuso de São Paulo.

### Níveis de acesso do conteúdo

`publico` (qualquer conta autenticada, mesmo sem plano válido), `paciente`
(exige acesso liberado) e `premium` (reservado para planos específicos, ainda
sem uso). Guias e alimentos nascem como `paciente`.

---

## 5. O motor da Troca Inteligente

Nenhuma combinação está escrita à mão. O cálculo tenta, nesta ordem:

1. equivalência cadastrada no sentido pedido;
2. a mesma equivalência lida ao contrário, se for bidirecional;
3. a razão entre as porções dos dois alimentos, dentro do mesmo grupo;
4. nada disso fechou → a tela diz o que falta, e não mostra número.

Três formatos de regra são aceitos: **proporcional** (o caso comum),
**tabela de pontos** (para trocas que não escalam em linha reta — interpola
entre os pontos e nunca extrapola) e **fixa**.

O caminho 3 é o que faz o catálogo crescer sozinho: cadastrar a porção de um
alimento novo já o habilita em todas as trocas do grupo dele.

---

## 6. Como fazer as coisas

### Adicionar um alimento

Área da nutricionista → **Alimentos** → **Novo alimento**. O campo que mais
importa é a porção: com ela preenchida, o alimento entra em todas as trocas do
grupo, sem escrever equivalência nenhuma. Sem ela, aparece como "sem porção" e
fica fora da calculadora — em vez de ganhar um valor inventado.

Para editar direto no código (os dados de partida), o arquivo é
`src/central/dados/sementes/alimentos.ts`. Depois de mexer, rode:

```bash
npm run seed        # regenera 0004_dados_iniciais.sql
npm run instalador  # regenera supabase/instalar.sql
```

### Adicionar uma equivalência

Área da nutricionista → **Equivalências** → **Nova equivalência**. Só é preciso
quando a troca **não** for a razão entre as porções — por exemplo quando a
lista de substituição traz um valor próprio para aquele par.

### Adicionar um restaurante ou categoria de comer fora

**Conteúdos** → aba **Comer fora** → **Nova categoria**. Cada categoria é um
conjunto de decisões ("a massa", "a proteína", "o molho"), e cada decisão tem
opções classificadas em melhor escolha / boa opção / mais ocasional. Categoria
em rascunho aparece só para você.

As calorias de cada opção têm um interruptor próprio: o número fica guardado
mesmo quando não é exibido.

### Adicionar um guia

**Conteúdos** → aba **Guias** → **Novo guia**. Cada seção tem título,
parágrafos e marcadores, escritos um por linha. Enquanto não houver seção
nenhuma, o guia aparece como "em breve" para o paciente.

### Mudar a identidade visual

Tudo no primeiro bloco de `src/central/styles/central.css`:

```css
.central {
  --primary: #3a6355;
  --background: #f6f4f1;
  --surface: #ffffff;
  --text: #1f1d1b;
  --border: #e6e1d9;
  --success: #3d6650;
  --warning: #7d5c14;
  --danger: #8f4034;
  --radius: 20px;
  --font-display: "Fraunces", Georgia, serif;
}
```

Nenhuma regra do arquivo escreve cor no meio do caminho. Depois de mexer, rode
`npm test`: há um teste que confere o contraste de cada par que aparece na tela
contra a régua da WCAG e diz qual combinação reprovou e por quanto.

### Mudar o WhatsApp, o nome e o lema

Área da nutricionista → **Configurações**. Não precisa publicar de novo. O lema
é a frase de identidade da tela inicial; deixar em branco esconde a linha.

---

## 7. O que foi verificado rodando

| Bateria | Como rodar | Resultado |
|---|---|---|
| Motor de cálculo e contraste | `npm test` | 32 testes |
| Segurança do banco | `npm run test:banco` | 61 verificações |
| Interface no navegador | Playwright, ver seção abaixo | 57 verificações |

A bateria de segurança sobe um Postgres limpo, aplica as migrações e assume a
identidade de sete pessoas diferentes para perguntar ao banco o que cada uma
consegue ver e fazer. Entre o que ela prova:

- paciente ativa lê conteúdo; expirada, suspensa, não iniciada e avulsa não;
- a URL protegida direta não devolve nada para quem não tem acesso;
- paciente não estica a própria data de fim, não se promove a admin, não mexe
  no cadastro de outra pessoa;
- paciente A não lê a linha, o perfil nem os favoritos do paciente B;
- renovar restaura o acesso sem duplicar paciente, e fica no histórico;
- quem se cadastra sozinho fica autenticado e sem acesso a nada;
- sem login, a leitura é barrada antes mesmo da política.

Precisa de um Postgres local:

```bash
npm run test:banco     # usa PGHOST=/tmp PGPORT=5433 por padrão
```

---

## 8. Modo demonstração

Sem as variáveis de ambiente do Supabase, o app abre inteiro com dados de
exemplo, sem login, e o que for salvo fica só no navegador. Uma faixa amarela
avisa o tempo todo.

Serve para três coisas: abrir o projeto e ver tudo antes de configurar serviço
nenhum; rodar a bateria de interface sem depender de rede; e continuar
trabalhando se o Supabase estiver fora do ar.

---

## 9. O app antigo de acompanhamento

O produto anterior deste repositório (check-in diário, plano alimentar, diário,
evolução, painel da nutricionista, base TACO) continua inteiro em `src/app/`,
`src/components/patient`, `src/components/nutri` e `src/repositories`.

Ele está **desligado por padrão**. Motivo: roda sobre dados fictícios em
memória e aceita qualquer senha, então não pode dividir endereço com a Central,
que vai ter paciente de verdade. Para usar em desenvolvimento, coloque
`VITE_APP_ANTIGO=1` no `.env.local` e acesse `/consultorio`.

Nada foi apagado. Quando for a vez de trazê-lo para o Supabase, o caminho já
está aberto: ele fala com `src/repositories/`, que é o mesmo formato de troca
que a Central usa em `dados/repositorio.ts`.

---

## 10. Comandos

```bash
npm install
npm run dev          # http://localhost:5173
npm test             # cálculo + contraste da paleta
npm run test:banco   # segurança do banco (precisa de Postgres local)
npm run typecheck
npm run lint
npm run build
npm run preview
npm run seed         # regenera 0004_dados_iniciais.sql das sementes
npm run instalador   # regenera supabase/instalar.sql
```

---

## 11. O que já está cadastrado, e o que falta

O briefing pede para não inventar valor nutricional nem recomendação. Tudo
abaixo veio dos seus materiais; onde eles não dizem, o campo fica vazio e a
tela mostra o estado de preparo.

**Do guia de refeição livre** — em Comer fora, sete categorias publicadas:

| Categoria | O que tem |
|---|---|
| Refeição livre | As 3 completas, as 7 meias, as bebidas e a conta (2 meias = 1 completa) |
| Hambúrguer | Montagem simples × densa, e a montagem completa do material |
| Comida japonesa | Entradas, combinados, temaki, fritos e molhos cremosos, com as 4 observações |
| Massas | As 3 montagens, com molho ao sugo, proteína e a dica do Spoleto |
| Pizza | 3 fatias de massa fina ou 2 de massa grossa, com a nota do recheio |
| Açaí | 500 ml como completa, 300 ml como meia |
| Doces e sobremesas | As 6 meias refeições doces |

Subway, Restaurantes e Delivery seguem reservados, sem conteúdo.

**Do guia de supermercado** — três guias no tema Compras: a regra de ouro dos
rótulos, as marcas por categoria (iogurte, pão de forma, geleia, frutas e
vegetais congelados, prontos) e a lista de proteínas para ter em casa.

**Do e-book de marmitas** — três guias no tema Marmitas: por onde começar
(higienização e armazenamento das frutas), as nove receitas da semana, e os
atalhos de quem está sem tempo, com os links de compra já clicáveis.

**Ainda sem conteúdo:** o guia "Variar em casa" (reservado para as suas ideias
de variação), os quatro guias de Digestão, os dois de Restrições, e
Industrializados, Doces, Álcool e Comer fora no tema do dia a dia.

**No catálogo de alimentos**, segue valendo o que veio da lista de
substituição: 1 equivalência (100 g de arroz = 80 g de macarrão), 2 alimentos
com porção e os 27 vegetais livres com a regra de 150 g. Os demais aparecem
como "sem porção" até você cadastrar.

**Conferir antes de publicar:** o WhatsApp `(31) 99450-3318` e o nome
`Isabela Marçal` foram lidos do rodapé dos seus materiais, e o lema entrou como
"Sexta é dia de variar, não de sair da dieta." Os três estão em Configurações,
na área da nutricionista, e mudam sem publicar de novo.

## 12. Preparado para depois

- **Conteúdo por plano ou por paciente**: a coluna `nivel_acesso` já existe em
  `alimentos` e `conteudos`; falta a tabela de exceção por paciente e mais uma
  condição na política.
- **Fotos e materiais**: o Supabase Storage já vem no projeto;
  `alimentos.imagem_url` e `conteudos.imagem_url` estão prontos.
- **Frações de porção**: `utils/porcoes.ts` já calcula "0,5 porção de arroz +
  0,5 de abóbora"; falta a tela.
- **Regras não lineares**: o motor já aceita tabela de pontos e regra fixa.
- **Pagamento**: fora de escopo por decisão do briefing. O controle financeiro é
  externo e a validade do acesso é manual.
- **200 pacientes**: o banco está indexado por status, data de fim e perfil; a
  lista é uma consulta só sobre uma tabela pequena. A ordem de grandeza que
  exigiria repensar algo é outra.
