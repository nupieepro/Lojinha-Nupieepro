# migrar-fotos-ibb (arquivada em 12/11/2026)
Função de uso único que migrava fotos do ImgBB para o Storage. Estava ativa, com `verify_jwt=false`, CORS `*` e
autenticada pela senha em texto puro `config.admin_senha` (padrão antigo, pré-C1). Como a chave `admin_senha` não
existe mais, ela só respondia 401, mas era um endpoint morto exposto. Foi substituída em produção por um stub que
responde **410 Gone**. O código original está arquivado
em `migrar-fotos-ibb.original.ts.txt` (nesta pasta). Para reutilizar, reescreva usando JWT de admin como em `upload-imagem`.
