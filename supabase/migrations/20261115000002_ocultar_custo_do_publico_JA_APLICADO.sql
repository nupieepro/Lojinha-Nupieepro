-- ============================================================================
-- OCULTAR `custo` DO PÚBLICO — aplicar SOMENTE DEPOIS que a nova loja (que lê por
-- listar_produtos_loja) estiver no ar. A loja antiga fazia select('*') em produtos
-- e quebraria sem a coluna liberada.
--
-- Problema encontrado em 15/11/2026: o papel anon (qualquer visitante) tinha SELECT
-- na coluna produtos.custo, ou seja, a margem de cada produto era pública pela API.
-- Correção: SELECT em nível de coluna, sem `custo`. O painel admin continua vendo o custo
-- (usa admin_get_produtos, SECURITY DEFINER).
-- Também remove privilégios desnecessários (TRUNCATE/REFERENCES/TRIGGER) do anon/authenticated.
-- Reverter: grant select on public.produtos to anon;
-- ============================================================================
revoke select on public.produtos from anon;
grant select (id, nome, descricao, preco, tipo, categoria, tamanhos, imagens, estoque, destaque, novo,
              encomenda, prazo_encomenda, badge_extra, ativo, agendamento,
              preco_promocional, promo_inicio, promo_fim, promo_rotulo)
  on public.produtos to anon;

revoke truncate, references, trigger on all tables in schema public from anon, authenticated;
