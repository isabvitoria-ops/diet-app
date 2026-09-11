import assert from "node:assert/strict";
import test from "node:test";
import type { Alimento, Equivalencia, GrupoAlimentar, Medida } from "@/central/types";
import { calcularTroca, type ContextoCalculo } from "./calculoTroca";
import { combinarPorcoes, emPorcoes, medidaDePorcoes } from "./porcoes";
import { arredondarExibicao, converter } from "./medidas";
import { catalogo } from "@/central/data/catalogo";

/**
 * Testes do motor de cálculo (§34 do briefing: "teste também exemplos
 * matemáticos manualmente"). Rodam com `npm test`, no runner nativo do
 * Node — sem nenhuma dependência de teste instalada.
 */

function grupo(id: string, trocaPorPorcao = true): GrupoAlimentar {
  return { id, nome: id, descricao: null, ordem: 1, regra: { tipo: "porcoes" }, trocaPorPorcao, tags: [] };
}

function alimento(id: string, extra: Partial<Alimento> = {}): Alimento {
  return {
    id,
    nome: id,
    grupoId: "carbo",
    unidadeBaseId: "g",
    porcao: null,
    medidas: [],
    atributos: { semGluten: null, semLactose: null },
    tags: [],
    imagem: null,
    observacao: null,
    ...extra,
  };
}

function contexto(alimentos: Alimento[], equivalencias: Equivalencia[], grupos: GrupoAlimentar[]): ContextoCalculo {
  return {
    alimento: (id) => alimentos.find((a) => a.id === id) ?? null,
    grupo: (id) => grupos.find((g) => g.id === id) ?? null,
    equivalenciasDe: (id) =>
      equivalencias.filter((e) => e.origemAlimentoId === id || (e.bidirecional && e.destinoAlimentoId === id)),
  };
}

const g = (quantidade: number): Medida => ({ quantidade, unidadeId: "g" });

// ---------------------------------------------------------------- o exemplo do briefing

test("o exemplo do briefing: 90 g de arroz viram 72 g de macarrão", () => {
  const arroz = catalogo.alimento("arroz-cozido");
  const macarrao = catalogo.alimento("macarrao-cozido");
  assert.ok(arroz && macarrao, "os dois alimentos precisam estar cadastrados");

  const r = calcularTroca({ alimentoOrigem: arroz, alimentoDestino: macarrao, medida: g(90) });
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.saida.quantidade, 72);
  assert.equal(r.saida.unidadeId, "g");
  assert.equal(r.origem, "regra-direta");
});

test("a mesma equivalência lida ao contrário: 80 g de macarrão voltam a ser 100 g de arroz", () => {
  const arroz = catalogo.alimento("arroz-cozido")!;
  const macarrao = catalogo.alimento("macarrao-cozido")!;
  const r = calcularTroca({ alimentoOrigem: macarrao, alimentoDestino: arroz, medida: g(80) });
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.saida.quantidade, 100);
  assert.equal(r.origem, "regra-invertida");
});

test("a troca escala: 45 g de arroz viram 36 g de macarrão", () => {
  const arroz = catalogo.alimento("arroz-cozido")!;
  const macarrao = catalogo.alimento("macarrao-cozido")!;
  const r = calcularTroca({ alimentoOrigem: arroz, alimentoDestino: macarrao, medida: g(45) });
  assert.ok(r.ok && r.saida.quantidade === 36);
});

// ---------------------------------------------------------------- porções (§8)

test("porções: 2 porções de arroz são 200 g e 1,6 porção são 160 g", () => {
  const arroz = catalogo.alimento("arroz-cozido")!;
  assert.deepEqual(medidaDePorcoes(arroz, 2), { quantidade: 200, unidadeId: "g" });
  assert.deepEqual(medidaDePorcoes(arroz, 1.6), { quantidade: 160, unidadeId: "g" });
  assert.equal(emPorcoes(arroz, g(150)), 1.5);
});

test("troca derivada só das porções, sem equivalência escrita", () => {
  const grupos = [grupo("carbo")];
  const a = alimento("a", { porcao: g(100) });
  const b = alimento("b", { porcao: g(50) });
  const ctx = contexto([a, b], [], grupos);

  const r = calcularTroca({ alimentoOrigem: a, alimentoDestino: b, medida: g(90) }, ctx);
  assert.equal(r.ok, true);
  if (!r.ok) return;
  assert.equal(r.saida.quantidade, 45);
  assert.equal(r.origem, "porcoes");
  assert.equal(r.porcoes, 0.9);
});

test("grupo com trocaPorPorcao desligado não deriva nada", () => {
  const grupos = [grupo("carbo", false)];
  const a = alimento("a", { porcao: g(100) });
  const b = alimento("b", { porcao: g(50) });
  const r = calcularTroca(
    { alimentoOrigem: a, alimentoDestino: b, medida: g(90) },
    contexto([a, b], [], grupos),
  );
  assert.equal(r.ok, false);
  if (r.ok) return;
  assert.equal(r.motivo, "sem-equivalencia");
});

test("alimento sem porção cadastrada não é estimado — devolve falha explicada", () => {
  const grupos = [grupo("carbo")];
  const a = alimento("a", { porcao: g(100) });
  const b = alimento("b");
  const r = calcularTroca({ alimentoOrigem: a, alimentoDestino: b, medida: g(90) }, contexto([a, b], [], grupos));
  assert.equal(r.ok, false);
  if (r.ok) return;
  assert.equal(r.motivo, "porcao-nao-cadastrada");
});

test("combinar frações de porção: 0,5 de um + 0,5 de outro", () => {
  const a = alimento("a", { porcao: g(100) });
  const b = alimento("b", { porcao: g(60) });
  const partes = combinarPorcoes([
    { alimento: a, fracao: 0.5 },
    { alimento: b, fracao: 0.5 },
  ]);
  assert.equal(partes[0]?.medida?.quantidade, 50);
  assert.equal(partes[1]?.medida?.quantidade, 30);
});

// ---------------------------------------------------------------- unidades (§5)

test("converte a unidade do paciente antes de aplicar a regra", () => {
  const grupos = [grupo("carbo")];
  const a = alimento("a", {
    porcao: g(100),
    medidas: [{ unidadeId: "colher-sopa", equivalenteNaBase: 25 }],
  });
  const b = alimento("b", { porcao: g(50) });
  // 4 colheres de sopa = 100 g = 1 porção → 50 g de b.
  const r = calcularTroca(
    { alimentoOrigem: a, alimentoDestino: b, medida: { quantidade: 4, unidadeId: "colher-sopa" } },
    contexto([a, b], [], grupos),
  );
  assert.ok(r.ok && r.saida.quantidade === 50);
  assert.equal(converter(a, { quantidade: 2, unidadeId: "colher-sopa" }, "g"), 50);
});

test("unidade não cadastrada no alimento não é convertida na marra", () => {
  const a = alimento("a", { porcao: g(100) });
  assert.equal(converter(a, { quantidade: 1, unidadeId: "fatia" }, "g"), null);
});

// ---------------------------------------------------------------- regras não lineares (§10)

test("regra em tabela interpola entre os pontos cadastrados", () => {
  const a = alimento("a");
  const b = alimento("b");
  const eq: Equivalencia = {
    id: "t",
    origemAlimentoId: "a",
    destinoAlimentoId: "b",
    regra: {
      tipo: "tabela",
      unidadeOrigemId: "g",
      unidadeDestinoId: "g",
      pontos: [
        { de: 50, para: 40 },
        { de: 100, para: 70 },
      ],
    },
    bidirecional: true,
    fonte: null,
    observacao: null,
  };
  const ctx = contexto([a, b], [eq], [grupo("carbo")]);
  const r = calcularTroca({ alimentoOrigem: a, alimentoDestino: b, medida: g(75) }, ctx);
  assert.ok(r.ok && r.saida.quantidade === 55);
});

test("regra em tabela trava nos extremos em vez de extrapolar", () => {
  const a = alimento("a");
  const b = alimento("b");
  const eq: Equivalencia = {
    id: "t",
    origemAlimentoId: "a",
    destinoAlimentoId: "b",
    regra: {
      tipo: "tabela",
      unidadeOrigemId: "g",
      unidadeDestinoId: "g",
      pontos: [
        { de: 50, para: 40 },
        { de: 100, para: 70 },
      ],
    },
    bidirecional: false,
    fonte: null,
    observacao: null,
  };
  const ctx = contexto([a, b], [eq], [grupo("carbo", false)]);
  const r = calcularTroca({ alimentoOrigem: a, alimentoDestino: b, medida: g(400) }, ctx);
  assert.ok(r.ok);
  if (!r.ok) return;
  assert.equal(r.saida.quantidade, 70);
  assert.match(r.observacoes.join(" "), /acima da faixa/);
});

test("regra fixa ignora a quantidade informada", () => {
  const a = alimento("a");
  const b = alimento("b");
  const eq: Equivalencia = {
    id: "f",
    origemAlimentoId: "a",
    destinoAlimentoId: "b",
    regra: { tipo: "fixa", para: { quantidade: 1, unidadeId: "unidade" } },
    bidirecional: true,
    fonte: null,
    observacao: null,
  };
  const ctx = contexto([a, b], [eq], [grupo("carbo", false)]);
  const r = calcularTroca({ alimentoOrigem: a, alimentoDestino: b, medida: g(999) }, ctx);
  assert.ok(r.ok && r.saida.quantidade === 1 && r.saida.unidadeId === "unidade");
  // Regra fixa não tem inverso: no sentido contrário não deve inventar nada.
  const volta = calcularTroca({ alimentoOrigem: b, alimentoDestino: a, medida: { quantidade: 1, unidadeId: "unidade" } }, ctx);
  assert.equal(volta.ok, false);
});

// ---------------------------------------------------------------- entradas inválidas

test("recusa quantidade zero, negativa e alimento igual", () => {
  const arroz = catalogo.alimento("arroz-cozido")!;
  const macarrao = catalogo.alimento("macarrao-cozido")!;
  assert.equal(calcularTroca({ alimentoOrigem: arroz, alimentoDestino: macarrao, medida: g(0) }).ok, false);
  assert.equal(calcularTroca({ alimentoOrigem: arroz, alimentoDestino: macarrao, medida: g(-5) }).ok, false);
  const igual = calcularTroca({ alimentoOrigem: arroz, alimentoDestino: arroz, medida: g(90) });
  assert.equal(igual.ok, false);
  if (igual.ok) return;
  assert.equal(igual.motivo, "mesmo-alimento");
});

test("par sem equivalência devolve falha, nunca um número", () => {
  const arroz = catalogo.alimento("arroz-cozido")!;
  const tomate = catalogo.alimento("tomate")!;
  const r = calcularTroca({ alimentoOrigem: arroz, alimentoDestino: tomate, medida: g(90) });
  assert.equal(r.ok, false);
});

// ---------------------------------------------------------------- arredondamento

test("arredonda grama para inteiro e unidade discreta para meio", () => {
  const grama = catalogo.unidade("g");
  const fatia = catalogo.unidade("fatia");
  assert.equal(arredondarExibicao(71.96, grama), 72);
  assert.equal(arredondarExibicao(7.24, grama), 7.2);
  assert.equal(arredondarExibicao(1.3, fatia), 1.5);
  assert.equal(arredondarExibicao(0.1, fatia), 0.5);
});
