-- ============================================================
-- STORAGE — bucket "produtos" (fotos de produtos)
-- Substitui o ImgBB/Imgur usados no admin.html: as fotos passam a
-- ser hospedadas no próprio projeto Supabase, sem depender de host
-- terceiro gratuito (que expira link e é bloqueado por algumas redes).
--
-- Upload só acontece pela Edge Function "upload-imagem" (usa a
-- service role, que ignora RLS), então aqui não liberamos INSERT
-- pra anon/authenticated — só leitura pública, igual um bucket
-- normal de CDN de imagens.
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('produtos', 'produtos', TRUE, 8388608, ARRAY['image/jpeg','image/png','image/webp','image/gif'])
ON CONFLICT (id) DO UPDATE SET
    public = TRUE,
    file_size_limit = 8388608,
    allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','image/gif'];

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'storage' AND tablename = 'objects' AND policyname = 'produtos_bucket_leitura_publica'
    ) THEN
        CREATE POLICY "produtos_bucket_leitura_publica" ON storage.objects
            FOR SELECT TO anon, authenticated
            USING (bucket_id = 'produtos');
    END IF;
END $$;
