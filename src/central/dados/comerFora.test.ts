import assert from "node:assert/strict";
import test from "node:test";
import { CATEGORIAS_COMER_FORA } from "./sementes/comerFora";
import { CONFIGURACOES } from "./sementes/configuracoes";

/**
 * A estrutura de Comer fora depois da reorganização: sem a aba "Refeição
 * livre", e com as casas (McDonald's, Burger King, Artesanal) dentro da
 * categoria, agrupadas por tipo.
 */

const porId = new Map(CATEGORIAS_COMER_FORA.map((c) => [c.id, c]));

test('a aba "Refeição livre" saiu', () => {
  assert.equal(porId.has("refeicao-livre"), false);
});

test("a conta que morava nela virou a frase do topo de Comer fora", () => {
  const frase = CONFIGURACOES.find((c) => c.chave === "comer_fora_introducao");
  assert.ok(frase, "a configuração precisa existir");
  assert.match(String(frase.valor), /duas meias refeições equivalem a uma completa/i);
});

test("hambúrguer tem as três casas, separadas em lanchonete e artesanal", () => {
  const casas = porId.get("hamburguer")?.estabelecimentos ?? [];
  assert.deepEqual(
    casas.map((c) => [c.nome, c.grupo]),
    [
      ["McDonald's", "Lanchonetes"],
      ["Burger King", "Lanchonetes"],
      ["Artesanal", "Artesanais"],
    ],
  );
});

test("massas tem o Spoleto e o italiano, separados por tipo de casa", () => {
  const casas = porId.get("massas")?.estabelecimentos ?? [];
  assert.deepEqual(
    casas.map((c) => [c.nome, c.grupo]),
    [
      ["Spoleto", "Montar no balcão"],
      ["Restaurante italiano", "Restaurantes"],
    ],
  );
});

test("cada casa com opções tem as três classificações, uma de cada", () => {
  const casas = CATEGORIAS_COMER_FORA.flatMap((c) => c.estabelecimentos).filter(
    (c) => c.opcoes.length > 0,
  );
  assert.ok(casas.length >= 5, "as casas cadastradas precisam estar aqui");
  for (const casa of casas) {
    const niveis = casa.opcoes.map((o) => o.nivel);
    assert.deepEqual(niveis, ["melhor", "boa", "ocasional"], `${casa.nome} saiu fora da ordem`);
  }
});

test("o total em kcal cresce de melhor escolha para mais ocasional", () => {
  for (const casa of CATEGORIAS_COMER_FORA.flatMap((c) => c.estabelecimentos)) {
    const totais = casa.opcoes.map((o) => o.energia?.kcal ?? null);
    if (totais.some((v) => v === null)) continue;
    const ordenado = [...totais].sort((a, b) => a! - b!);
    assert.deepEqual(totais, ordenado, `${casa.nome}: a ordem das kcal não acompanha a classificação`);
  }
});

test("os totais em kcal batem com a soma dos itens", () => {
  for (const categoria of CATEGORIAS_COMER_FORA) {
    for (const casa of categoria.estabelecimentos) {
      for (const opcao of casa.opcoes) {
        const soma = opcao.detalhes
          .map((d) => Number(d.match(/(\d+) kcal/)?.[1] ?? NaN))
          .filter((n) => !Number.isNaN(n))
          .reduce((a, b) => a + b, 0);
        if (soma > 0 && opcao.energia?.kcal) {
          assert.equal(
            opcao.energia.kcal,
            soma,
            `${casa.nome} · ${opcao.titulo}: total ${opcao.energia.kcal} ≠ soma ${soma}`,
          );
        }
      }
    }
  }
});

test("o que é estimativa diz que é estimativa", () => {
  const estimadas = ["hamburgueria-artesanal", "restaurante-italiano"];
  for (const id of estimadas) {
    const casa = CATEGORIAS_COMER_FORA.flatMap((c) => c.estabelecimentos).find((c) => c.id === id);
    assert.ok(casa, `${id} precisa existir`);
    assert.match(casa.observacoes.join(" "), /estimativa/i, `${id} sem aviso nas observações`);
    assert.match(casa.resumo ?? "", /estimad/i, `${id} sem aviso no resumo`);
    for (const opcao of casa.opcoes) {
      assert.match(opcao.energia?.observacao ?? "", /estimativa/i, `${id} · ${opcao.titulo}`);
    }
  }
});

test("as marcas com logo têm logo; quem não tem cai na inicial", () => {
  const casas = porId.get("hamburguer")?.estabelecimentos ?? [];
  const comLogo = casas.filter((c) => c.logo !== null).map((c) => c.nome);
  assert.deepEqual(comLogo, ["McDonald's", "Burger King", "Artesanal"]);
  for (const casa of casas) {
    if (casa.logo) assert.match(casa.logo, /^data:image\//, `${casa.nome} precisa ser embutida`);
  }
});

test("o Subway está publicado com as três montagens", () => {
  const subway = porId.get("subway");
  assert.equal(subway?.status, "publicado");
  const opcoes = subway?.decisoes.flatMap((d) => d.opcoes) ?? [];
  assert.deepEqual(opcoes.map((o) => o.nivel), ["melhor", "boa", "ocasional"]);
});

test("identificador de casa não se repete dentro da categoria", () => {
  for (const categoria of CATEGORIAS_COMER_FORA) {
    const ids = categoria.estabelecimentos.map((c) => c.id);
    assert.equal(new Set(ids).size, ids.length, `${categoria.nome} tem casa repetida`);
  }
});

test("a ordem das categorias não tem buraco nem repetição", () => {
  const ordens = CATEGORIAS_COMER_FORA.map((c) => c.ordem).sort((a, b) => a - b);
  assert.deepEqual(ordens, [1, 2, 3, 4, 5, 6, 7, 8, 9]);
});
