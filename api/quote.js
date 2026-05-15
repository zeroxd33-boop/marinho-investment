const FREE_TICKERS = new Set(['PETR4', 'MGLU3', 'VALE3', 'ITUB4']);

module.exports = async function handler(req, res) {
  const ticker = String(req.query?.ticker || '')
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');

  if (!ticker) {
    return res.status(400).json({ error: 'ticker_obrigatorio' });
  }

  const token = process.env.BRAPI_TOKEN;
  if (!token && !FREE_TICKERS.has(ticker)) {
    return res.status(401).json({
      error: 'brapi_token_necessario',
      message: 'Configure BRAPI_TOKEN na Vercel para consultar ativos fora da lista gratuita da brapi.'
    });
  }

  const params = new URLSearchParams({
    range: '1d',
    interval: '1d',
    fundamental: 'true'
  });

  try {
    const response = await fetch(`https://brapi.dev/api/quote/${ticker}?${params.toString()}`, {
      headers: token ? { Authorization: `Bearer ${token}` } : {}
    });

    const data = await response.json().catch(() => ({}));

    if (!response.ok) {
      return res.status(502).json({
        error: 'cotacao_indisponivel',
        status: response.status,
        details: data
      });
    }

    return res.status(200).json(data);
  } catch (error) {
    return res.status(502).json({
      error: 'falha_ao_consultar_brapi',
      message: error.message
    });
  }
};
