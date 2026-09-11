/**
 * Gera `supabase/migracoes/0004_dados_iniciais.sql` a partir dos arquivos de
 * dados em TypeScript.
 *
 * Existe para que o seed do banco e os dados que o app usa em modo local não
 * possam divergir: há uma fonte só, e o SQL é derivado dela. Rode com
 * `npm run seed` sempre que mexer em src/central/dados/sementes/.
 */
import { writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const { UNIDADES } = await import("@/central/dados/sementes/unidades.ts");
const { GRUPOS } = await import("@/central/dados/sementes/grupos.ts");
const { ALIMENTOS } = await import("@/central/dados/sementes/alimentos.ts");
const { EQUIVALENCIAS } = await import("@/central/dados/sementes/equivalencias.ts");
const { CATEGORIAS_COMER_FORA } = await import("@/central/dados/sementes/comerFora.ts");
const { GUIAS } = await import("@/central/dados/sementes/guias.ts");
const { PLANOS } = await import("@/central/dados/sementes/planos.ts");
const { CONFIGURACOES } = await import("@/central/dados/sementes/configuracoes.ts");

const txt = (v) => (v === null || v === undefined ? "null" : `'${String(v).replace(/'/g, "''")}'`);
const num = (v) => (v === null || v === undefined ? "null" : String(v));
const bool = (v) => (v === null || v === undefined ? "null" : v ? "true" : "false");
const arr = (v) => (v && v.length ? `array[${v.map(txt).join(", ")}]::text[]` : "'{}'::text[]");
const json = (v) => `${txt(JSON.stringify(v ?? {}))}::jsonb`;

const linhas = [];
const p = (s) => linhas.push(s);

p(`-- =============================================================================
-- CENTRAL DO PACIENTE — 0004: dados iniciais
--
-- ARQUIVO GERADO. Não edite à mão: ele sai de src/central/dados/sementes/
-- pelo comando \`npm run seed\`. Editar aqui faz o banco e o modo local do app
-- discordarem na primeira vez que alguém rodar o gerador de novo.
--
-- Tudo é \`on conflict do nothing\`: rodar duas vezes não duplica nem apaga o
-- que você já tiver cadastrado pelo painel.
-- =============================================================================
`);

p("-- Planos ----------------------------------------------------------------------");
for (const x of PLANOS) {
  p(`insert into planos (id, nome, duracao_dias, descricao, ordem, ativo) values (${txt(x.id)}, ${txt(x.nome)}, ${num(x.duracaoDias)}, ${txt(x.descricao)}, ${num(x.ordem)}, true) on conflict (id) do nothing;`);
}

p("\n-- Unidades --------------------------------------------------------------------");
UNIDADES.forEach((x, i) => {
  p(`insert into unidades (id, rotulo, abreviacao, singular, continua, ordem) values (${txt(x.id)}, ${txt(x.rotulo)}, ${txt(x.abreviacao)}, ${txt(x.singular)}, ${bool(x.continua)}, ${i}) on conflict (id) do nothing;`);
});

p("\n-- Grupos alimentares ----------------------------------------------------------");
for (const x of GRUPOS) {
  p(`insert into grupos_alimentares (id, nome, descricao, ordem, regra, troca_por_porcao, tags) values (${txt(x.id)}, ${txt(x.nome)}, ${txt(x.descricao)}, ${num(x.ordem)}, ${x.regra ? json(x.regra) : "null"}, ${bool(x.trocaPorPorcao)}, ${arr(x.tags)}) on conflict (id) do nothing;`);
}

p("\n-- Alimentos -------------------------------------------------------------------");
for (const x of ALIMENTOS) {
  p(`insert into alimentos (id, nome, grupo_id, unidade_base_id, porcao_quantidade, porcao_unidade_id, medidas, sem_gluten, sem_lactose, tags, observacao) values (${txt(x.id)}, ${txt(x.nome)}, ${txt(x.grupoId)}, ${txt(x.unidadeBaseId)}, ${num(x.porcao?.quantidade ?? null)}, ${txt(x.porcao?.unidadeId ?? null)}, ${json(x.medidas)}, ${bool(x.atributos.semGluten)}, ${bool(x.atributos.semLactose)}, ${arr(x.tags)}, ${txt(x.observacao)}) on conflict (id) do nothing;`);
}

p("\n-- Equivalências ---------------------------------------------------------------");
for (const x of EQUIVALENCIAS) {
  p(`insert into equivalencias (id, origem_alimento_id, destino_alimento_id, tipo, regra, bidirecional, fonte, observacao) values (${txt(x.id)}, ${txt(x.origemAlimentoId)}, ${txt(x.destinoAlimentoId)}, ${txt(x.regra.tipo)}, ${json(x.regra)}, ${bool(x.bidirecional)}, ${txt(x.fonte)}, ${txt(x.observacao)}) on conflict (id) do nothing;`);
}

p("\n-- Comer fora ------------------------------------------------------------------");
for (const x of CATEGORIAS_COMER_FORA) {
  const corpo = { introducao: x.introducao, decisoes: x.decisoes, lembretes: x.lembretes };
  p(`insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values (${txt(x.id)}, 'comer_fora', ${txt(x.nome)}, null, ${txt(x.resumo)}, ${txt(x.icone)}, ${num(x.ordem)}, ${txt(x.status === "publicado" ? "publicado" : "rascunho")}, ${json(corpo)}, ${arr(x.tags)}) on conflict (id) do nothing;`);
}

p("\n-- Guias -----------------------------------------------------------------------");
for (const x of GUIAS) {
  p(`insert into conteudos (id, tipo, titulo, tema, resumo, icone, ordem, status, corpo, tags) values (${txt(x.id)}, 'guia', ${txt(x.titulo)}, ${txt(x.tema)}, ${txt(x.resumo)}, null, ${num(x.ordem)}, ${txt(x.status === "publicado" ? "publicado" : "rascunho")}, ${json({ secoes: x.secoes })}, ${arr(x.tags)}) on conflict (id) do nothing;`);
}

p("\n-- Configurações ---------------------------------------------------------------");
for (const x of CONFIGURACOES) {
  p(`insert into configuracoes (chave, valor, descricao) values (${txt(x.chave)}, ${json(x.valor)}, ${txt(x.descricao)}) on conflict (chave) do nothing;`);
}

p("");
const destino = fileURLToPath(new URL("../supabase/migracoes/0004_dados_iniciais.sql", import.meta.url));
writeFileSync(destino, linhas.join("\n"));
console.log(`0004_dados_iniciais.sql gerado — ${linhas.length} linhas`);
