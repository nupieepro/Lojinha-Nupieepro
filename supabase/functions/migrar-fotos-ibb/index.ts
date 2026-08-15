// ============================================================
// EDGE FUNCTION — migrar-fotos-ibb (uso único / manutenção)
// Varre public.produtos por linhas cuja `imagens` ainda aponta pro
// i.ibb.co, baixa cada foto, sobe pro bucket "produtos" do Storage
// e atualiza a linha com a nova URL. Idempotente: só mexe em linhas
// que ainda contêm um link ibb.co, então pode rodar de novo sem
// problema (ex.: se um produto tiver mais de uma imagem separada
// por vírgula e só algumas já tiverem sido migradas).
//
// Mesma checagem de senha que as demais RPCs/functions admin.
// ============================================================
import { createClient } from 'jsr:@supabase/supabase-js@2';

const BUCKET = 'produtos';
const CONTENT_TYPE_EXT: Record<string, string> = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
};

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

async function migrarUmaUrl(admin: ReturnType<typeof createClient>, url: string): Promise<string> {
  const res = await fetch(url);
  if (!res.ok) throw new Error(`fetch falhou (${res.status}) em ${url}`);
  const contentType = res.headers.get('content-type') || 'image/jpeg';
  const buf = new Uint8Array(await res.arrayBuffer());
  const extPorTipo = CONTENT_TYPE_EXT[contentType.split(';')[0].trim()];
  const extPorUrl = url.split('.').pop()?.split(/[?#]/)[0].toLowerCase();
  const ext = extPorTipo || (extPorUrl && /^[a-z0-9]{2,4}$/.test(extPorUrl) ? extPorUrl : 'jpg');
  const nomeArquivo = `${crypto.randomUUID()}.${ext}`;

  const { error: erroUpload } = await admin.storage
    .from(BUCKET)
    .upload(nomeArquivo, buf, { contentType, upsert: false });
  if (erroUpload) throw new Error(`upload falhou: ${erroUpload.message}`);

  const { data: pub } = admin.storage.from(BUCKET).getPublicUrl(nomeArquivo);
  return pub.publicUrl;
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS_HEADERS });
  if (req.method !== 'POST') return jsonResponse({ error: 'Método não permitido' }, 405);

  const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
  const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const admin = createClient(supabaseUrl, serviceRoleKey);

  try {
    const body = await req.json().catch(() => ({}));
    const chave = body?.chave;
    if (typeof chave !== 'string' || !chave) return jsonResponse({ error: 'Senha ausente' }, 400);

    const { data: config, error: erroConfig } = await admin
      .from('config')
      .select('valor')
      .eq('chave', 'admin_senha')
      .maybeSingle();
    if (erroConfig || !config?.valor || config.valor !== chave) {
      return jsonResponse({ error: 'Senha incorreta' }, 401);
    }

    const { data: produtos, error: erroSelect } = await admin
      .from('produtos')
      .select('id, nome, imagens')
      .ilike('imagens', '%ibb.co%');
    if (erroSelect) return jsonResponse({ error: erroSelect.message }, 500);

    const resultados: Array<{ id: number; nome: string; ok: boolean; de?: string; para?: string; erro?: string }> = [];

    for (const p of produtos || []) {
      const urls = (p.imagens || '').split(',').map((u: string) => u.trim()).filter(Boolean);
      const novasUrls: string[] = [];
      let falhou = false;
      for (const url of urls) {
        if (!url.includes('ibb.co')) { novasUrls.push(url); continue; }
        try {
          const novaUrl = await migrarUmaUrl(admin, url);
          novasUrls.push(novaUrl);
          resultados.push({ id: p.id, nome: p.nome, ok: true, de: url, para: novaUrl });
        } catch (e) {
          falhou = true;
          novasUrls.push(url); // mantém a antiga se der erro
          resultados.push({ id: p.id, nome: p.nome, ok: false, de: url, erro: e instanceof Error ? e.message : String(e) });
        }
      }
      if (!falhou || novasUrls.some((u) => !u.includes('ibb.co'))) {
        const { error: erroUpdate } = await admin
          .from('produtos')
          .update({ imagens: novasUrls.join(',') })
          .eq('id', p.id);
        if (erroUpdate) resultados.push({ id: p.id, nome: p.nome, ok: false, erro: `update falhou: ${erroUpdate.message}` });
      }
    }

    return jsonResponse({ total: resultados.length, resultados });
  } catch (e) {
    return jsonResponse({ error: e instanceof Error ? e.message : 'Erro inesperado' }, 500);
  }
});
