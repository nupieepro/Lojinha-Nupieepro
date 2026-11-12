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
//
// verify_jwt=false no deploy/config.toml: esse é só o gate de
// plataforma do Supabase (que exigiria um JWT válido antes mesmo
// de invocar a function). A autorização de verdade é feita AQUI
// dentro, validando o JWT manualmente via admin.auth.getUser() e
// checando admin_users — mais robusto que o gate de plataforma
// porque também confirma que o usuário é admin, não só que tem
// uma sessão válida qualquer.
// ============================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const BUCKET = 'produtos';
const TAMANHO_MAX = 8 * 1024 * 1024; // 8MB
const TIPOS_ACEITOS = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];

// Origens autorizadas a chamar a função (CORS). A autenticação é por Bearer
// token (não por cookie), então o risco de CORS aberto era baixo, mas não há
// motivo para aceitar outros sites.
const ORIGENS_PERMITIDAS = new Set([
  'https://nupieepro.github.io',
  'http://localhost:8000',
  'http://127.0.0.1:8000',
]);

function corsHeaders(req: Request) {
  const origem = req.headers.get('origin') || '';
  return {
    'Access-Control-Allow-Origin': ORIGENS_PERMITIDAS.has(origem) ? origem : 'https://nupieepro.github.io',
    'Vary': 'Origin',
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
  };
}

function jsonResponse(req: Request, body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders(req),
      'Content-Type': 'application/json',
      'X-Content-Type-Options': 'nosniff',
      'Cache-Control': 'no-store',
    },
  });
}

// Detecta o tipo REAL do arquivo pelos primeiros bytes (magic bytes).
// O campo `type` do formulário é controlado pelo cliente e não prova nada:
// um .html/.svg com Content-Type "image/png" viraria XSS armazenado no bucket público.
function detectarTipo(b: Uint8Array): { mime: string; ext: string } | null {
  const ascii = (i: number, n: number) => String.fromCharCode(...b.slice(i, i + n));
  if (b.length >= 3 && b[0] === 0xff && b[1] === 0xd8 && b[2] === 0xff) return { mime: 'image/jpeg', ext: 'jpg' };
  if (b.length >= 8 && b[0] === 0x89 && ascii(1, 3) === 'PNG' && b[4] === 0x0d && b[5] === 0x0a && b[6] === 0x1a && b[7] === 0x0a) return { mime: 'image/png', ext: 'png' };
  if (b.length >= 6 && (ascii(0, 6) === 'GIF87a' || ascii(0, 6) === 'GIF89a')) return { mime: 'image/gif', ext: 'gif' };
  if (b.length >= 12 && ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WEBP') return { mime: 'image/webp', ext: 'webp' };
  return null;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders(req) });
  if (req.method !== 'POST') return jsonResponse(req, { error: 'Método não permitido' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  try {
    const authHeader = req.headers.get('authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    if (!token) return jsonResponse(req, { error: 'Não autenticado' }, 401);

    const { data: userData, error: erroUser } = await admin.auth.getUser(token);
    if (erroUser || !userData?.user) return jsonResponse(req, { error: 'Sessão inválida' }, 401);

    const { data: adminRow, error: erroAdmin } = await admin
      .from('admin_users')
      .select('user_id')
      .eq('user_id', userData.user.id)
      .maybeSingle();
    if (erroAdmin || !adminRow) return jsonResponse(req, { error: 'Acesso negado' }, 403);

    const form = await req.formData();
    const arquivo = form.get('arquivo');
    if (!(arquivo instanceof File)) return jsonResponse(req, { error: 'Arquivo ausente' }, 400);
    if (!TIPOS_ACEITOS.includes(arquivo.type)) return jsonResponse(req, { error: 'Tipo de arquivo não aceito' }, 400);
    if (arquivo.size > TAMANHO_MAX) return jsonResponse(req, { error: 'Arquivo maior que 8MB' }, 400);

    // Confere o conteúdo real; ignora extensão e MIME enviados pelo cliente.
    const bytes = new Uint8Array(await arquivo.arrayBuffer());
    const real = detectarTipo(bytes);
    if (!real || !TIPOS_ACEITOS.includes(real.mime)) {
      return jsonResponse(req, { error: 'Conteúdo do arquivo não é uma imagem válida' }, 400);
    }
    const nomeArquivo = `${crypto.randomUUID()}.${real.ext}`;

    const { error: erroUpload } = await admin.storage
      .from(BUCKET)
      .upload(nomeArquivo, bytes, { contentType: real.mime, upsert: false });
    if (erroUpload) {
      console.error('upload-imagem: falha no upload', erroUpload.message);
      return jsonResponse(req, { error: 'Falha ao salvar a imagem' }, 500);
    }

    const { data: pub } = admin.storage.from(BUCKET).getPublicUrl(nomeArquivo);
    return jsonResponse(req, { url: pub.publicUrl });
  } catch (e) {
    console.error('upload-imagem: erro inesperado', e instanceof Error ? e.message : e);
    return jsonResponse(req, { error: 'Erro inesperado' }, 500);
  }
});
