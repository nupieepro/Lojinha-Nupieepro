// ============================================================
// EDGE FUNCTION — resend-email  (cópia fiel da v8 em produção, versionada em 12/11/2026)
// Acionada pelo trigger _notify_email_on_pedidos() (pg_net) em INSERT/UPDATE de pedidos.
// Envia e-mail ao financeiro e ao cliente via Gmail SMTP.
// Secrets: SMTP_USER, SMTP_PASSWORD (senha de app do Gmail); opcionais EMAIL_FINANCEIRO, NOME_LOJA.
// verify_jwt=true: o trigger chama com Bearer = service role key (Vault: service_role_key_notify_pedidos).
//
// TODO de segurança (ver docs/05-SEGURANCA.md): escapar `p.nome` e `i.nome` no HTML (HTML injection
// no e-mail), tirar CHAVE_PIX fixa e trocar Gmail SMTP por provedor transacional com SPF/DKIM.
// ============================================================
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { SmtpClient } from "https://deno.land/x/smtp@v0.7.0/mod.ts";

const SMTP_USER = Deno.env.get("SMTP_USER")!;
const SMTP_PASSWORD = Deno.env.get("SMTP_PASSWORD")!;
const EMAIL_FINANCEIRO = Deno.env.get("EMAIL_FINANCEIRO") || "financeironupieepro@gmail.com";
const NOME_LOJA = Deno.env.get("NOME_LOJA") || "NUPIEEPRO STORE";
const CHAVE_PIX = "financeironupieepro@gmail.com";

const brl = (n = 0) => Number(n || 0).toFixed(2).replace(".", ",");

async function enviarEmail(to: string | string[], subject: string, html: string) {
  const client = new SmtpClient();
  await client.connectTLS({
    hostname: "smtp.gmail.com",
    port: 465,
    username: SMTP_USER,
    password: SMTP_PASSWORD,
  });

  await client.send({
    from: `${NOME_LOJA} <${SMTP_USER}>`,
    to: Array.isArray(to) ? to : to.split(","),
    subject: subject,
    content: html,
    html: html,
  });

  await client.close();
}

function htmlPedido(p: any, paraFinanceiro = false) {
  const titulo = paraFinanceiro ? "NOVO PEDIDO RECEBIDO" : "PEDIDO CONFIRMADO!";
  return `
    <div style="font-family:Arial;max-width:600px;border:1px solid #eee">
      <div style="background:#0f0732;padding:20px;text-align:center">
        <h1 style="color:#f85900;margin:0">${titulo}</h1>
        <p style="color:#fff;margin:0">#${p.numero} - ${NOME_LOJA}</p>
      </div>
      <div style="padding:20px">
        <p>Olá, <b>${p.nome}</b>!</p>
        <p>Resumo do pedido:</p>
        <table style="width:100%;border-collapse:collapse">
          ${p.itens?.map((i: any) => `<tr><td style="padding:8px 0">${i.qtd}x ${i.nome}</td><td style="text-align:right">R$ ${brl(i.preco * i.qtd)}</td></tr>`).join('')}
          <tr><td style="padding:8px 0;font-weight:bold">TOTAL</td><td style="text-align:right;font-weight:bold;color:#f85900">R$ ${brl(p.total)}</td></tr>
        </table>
        <div style="margin-top:20px;padding:15px;background:#f9f9f9;border-radius:8px">
          <b>Pagamento:</b> ${p.pagamento}<br>
          ${p.pagamento === 'PIX' ? `<b>Chave PIX:</b> ${CHAVE_PIX}` : ''}
        </div>
      </div>
      <div style="background:#eee;padding:10px;text-align:center;font-size:12px">NUPIEEPRO - UFPI</div>
    </div>
  `;
}

serve(async (req) => {
  try {
    const { event, record } = await req.json();

    if (event === "INSERT") {
      await enviarEmail(
        EMAIL_FINANCEIRO,
        `🛒 Novo Pedido #${record.numero} - ${record.nome}`,
        htmlPedido(record, true)
      );

      if (record.email) {
        await enviarEmail(
          record.email,
          `✅ Pedido #${record.numero} Confirmado - ${NOME_LOJA}`,
          htmlPedido(record, false)
        );
      }
    }

    return new Response(JSON.stringify({ ok: true }), { status: 200 });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), { status: 500 });
  }
});
