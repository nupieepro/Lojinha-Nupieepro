// ============================================================
// EDGE FUNCTION — upload-imagem
// Recebe uma foto de produto do painel admin, confere a senha
// admin (mesma lógica de public._validar_admin) e sobe o arquivo
// pro Storage usando a service role — assim o bucket "produtos"
// não precisa liberar INSERT pra ninguém além desta function.
// ============================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const BUCKET = 'produtos';
const TAMANHO_MAX = 8 * 1024 * 1024; // 8MB
const TIPOS_ACEITOS = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return jsonResponse({ error: 'Método não permitido' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  try {
    const form = await req.formData();
    const chave = form.get('chave');
    const arquivo = form.get('arquivo');

    if (typeof chave !== 'string' || !chave) return jsonResponse({ error: 'Senha ausente' }, 400);
    if (!(arquivo instanceof File)) return jsonResponse({ error: 'Arquivo ausente' }, 400);

    // Mesma checagem que public._validar_admin faz no banco — senha fica só no config, nunca no código.
    const { data: config, error: erroConfig } = await admin
      .from('config')
      .select('valor')
      .eq('chave', 'admin_senha')
      .maybeSingle();
    if (erroConfig || !config?.valor || config.valor !== chave) {
      return jsonResponse({ error: 'Senha incorreta' }, 401);
    }

    if (!TIPOS_ACEITOS.includes(arquivo.type)) return jsonResponse({ error: 'Tipo de arquivo não aceito' }, 400);
    if (arquivo.size > TAMANHO_MAX) return jsonResponse({ error: 'Arquivo maior que 8MB' }, 400);

    const extensao = (arquivo.name.split('.').pop() || 'jpg').toLowerCase().replace(/[^a-z0-9]/g, '') || 'jpg';
    const nomeArquivo = `${crypto.randomUUID()}.${extensao}`;

    const { error: erroUpload } = await admin.storage
      .from(BUCKET)
      .upload(nomeArquivo, arquivo, { contentType: arquivo.type, upsert: false });
    if (erroUpload) return jsonResponse({ error: erroUpload.message }, 500);

    const { data: pub } = admin.storage.from(BUCKET).getPublicUrl(nomeArquivo);
    return jsonResponse({ url: pub.publicUrl });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : 'Erro inesperado' }, 500);
  }
});
