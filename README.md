# Consultório — PWA da nutricionista e do paciente

App de integração entre paciente e profissional: acompanhamento nutricional diário (check-in, plano alimentar, diário, evolução) e o painel de trabalho da nutricionista (pacientes, plano, base TACO, feed, dashboard).

PWA — Vite + React + TypeScript + Supabase (hoje sobre um mock em memória, ver `ARCHITECTURE.md`).

## Rodando localmente

```bash
npm install
npm run dev       # http://localhost:5173
```

Login de teste (senha: qualquer coisa com 4+ caracteres):
- Nutricionista: `nutri@consultorio.com` — pede MFA no primeiro acesso de cada dispositivo (código: qualquer sequência de 6 dígitos, é mock).
- Paciente (Marina, ativa): `marina@email.com`
- Paciente (Helena, acesso encerrado — deve ser rejeitado): `helena@email.com`

## Outros comandos

```bash
npm run build      # build de produção + typecheck + PWA (manifest/service worker)
npm run preview    # serve o build de produção localmente
npm run typecheck  # só typecheck, sem build
```

## Documentação

Ver `ARCHITECTURE.md` para a arquitetura completa, o mapeamento de cada regra de negócio para o código, e o que fica para uma próxima etapa (Supabase real, upload de fotos, etc).
