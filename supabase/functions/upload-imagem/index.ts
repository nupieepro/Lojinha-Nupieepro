// ============================================================
// EDGE FUNCTION — upload-imagem
// Recebe uma foto de produto do painel admin e sobe pro Storage
// usando a service role — assim o bucket "produtos" não precisa
// liberar INSERT pra ninguém além desta function.
//
// Autorização: valida o JWT do Supabase Auth enviado no header
// Authorization e confere se o usuário é admin (existe em
// public.admin_users) — mesmo padrão usado pelas RPCs admin_*
// depois da migração para Supabase Auth (C1). Não recebe mais
// senha em nenhum campo do formulário.
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
    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return jsonResponse({ error: 'Não autenticado' }, 401);

    const { data: userData, error: erroUser } = await admin.auth.getUser(token);
    if (erroUser || !userData?.user) return jsonResponse({ error: 'Sessão inválida' }, 401);

    const { data: adminRow, error: erroAdmin } = await admin
      .from('admin_users')
      .select('user_id')
      .eq('user_id', userData.user.id)
      .maybeSingle();
    if (erroAdmin || !adminRow) return jsonResponse({ error: 'Acesso negado' }, 403);

    const form = await req.formData();
    const arquivo = form.get('arquivo');
    if (!(arquivo instanceof File)) return jsonResponse({ error: 'Arquivo ausente' }, 400);
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
