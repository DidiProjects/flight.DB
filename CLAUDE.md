# flight.DB — Instruções para Claude

## Arquitetura atual (2026-04-24)

- **flight.DB**: container Docker, PostgreSQL 16, timezone America/Sao_Paulo
- **Deploy:** GitHub Actions → Tailscale + SSH → rsync → `docker build` → `docker run`
- **Init scripts:** `init-scripts/01-schema.sql` (schema) + `init-scripts/02-seed.sh` (seed Airlines + admin)
  - Executados **apenas na primeira inicialização** do volume Docker
- **Design completo:** `design.md` na raiz — schema, rotas, fluxo, decisões aprovadas

## Início de cada sessão

1. Ler `memory/MEMORY.md` (índice da memória persistente)
2. Ler os arquivos relevantes ao trabalho da sessão:
   - `memory/flight-api-design.md` — schema, rotas, fluxo, decisões aprovadas
   - `memory/feedback-dev-style.md` — preferências de desenvolvimento
3. Se o trabalho envolver mudanças de schema: ler `design.md`

## Final de cada sessão (ou quando tokens estiverem acabando)

Atualizar a memória com tudo que foi aprendido na sessão:
- Mudanças de schema ou decisões de arquitetura → `memory/flight-api-design.md`
- Preferências ou feedbacks do usuário → `memory/feedback-dev-style.md`
- Atualizar `memory/MEMORY.md` se novos arquivos foram criados

## Regras permanentes

### Dados sensíveis na memória
NUNCA armazenar na memória: credenciais, senhas, tokens, API keys, dados pessoais (CPF, passaporte, cartão), ou qualquer informação que possa identificar pessoas reais.
A memória fica versionada no git, dados sensíveis não devem entrar no histórico.

### Autonomia
Operar com máxima autonomia. Não pedir confirmação a não ser em risco real de perda de dados irreversível.
