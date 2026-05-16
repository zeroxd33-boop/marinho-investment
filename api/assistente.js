module.exports = async function handler(req, res) {
  if (req.method !== 'POST') {
    return res.status(405).json({ error: 'metodo_nao_permitido' });
  }

  const apiKey = process.env.GROQ_API_KEY;
  if (!apiKey) {
    return res.status(401).json({
      error: 'groq_key_necessaria',
      message: 'Configure GROQ_API_KEY na Vercel para usar o Assistente de Carteira.'
    });
  }

  try {
    const rawBody = req.body ?? await readJsonBody(req);
    const body = typeof rawBody === 'string' ? JSON.parse(rawBody || '{}') : rawBody || {};
    const carteira = Array.isArray(body.carteira) ? body.carteira.slice(0, 60) : [];
    const metaRenda = Number(body.metaRenda) || 0;

    if (!carteira.length) {
      return res.status(400).json({ error: 'carteira_vazia' });
    }

    const resumo = carteira.map(item => ({
      ticker: String(item.ticker || '').slice(0, 16),
      tipo: item.tipo,
      setor: item.setor || 'Nao informado',
      quantidade: Number(item.quantidade) || 0,
      preco_medio: Number(item.preco_medio) || 0,
      cotacao_atual: Number(item.cotacao_atual) || Number(item.preco_medio) || 0,
      dividendo_mensal: Number(item.dividendo_mensal) || 0
    }));
    const totais = resumo.reduce((acc, item) => {
      const quantidade = Number(item.quantidade) || 0;
      const precoMedio = Number(item.preco_medio) || 0;
      const cotacaoAtual = Number(item.cotacao_atual) || precoMedio;
      const investido = quantidade * precoMedio;
      const atual = quantidade * cotacaoAtual;

      acc.valor_investido += investido;
      acc.valor_atual += atual;
      acc.renda_mensal_estimada += Number(item.dividendo_mensal) || 0;
      acc.por_tipo[item.tipo || 'nao_informado'] = (acc.por_tipo[item.tipo || 'nao_informado'] || 0) + atual;
      acc.por_setor[item.setor || 'Nao informado'] = (acc.por_setor[item.setor || 'Nao informado'] || 0) + atual;
      return acc;
    }, {
      valor_investido: 0,
      valor_atual: 0,
      renda_mensal_estimada: 0,
      por_tipo: {},
      por_setor: {}
    });
    totais.resultado = totais.valor_atual - totais.valor_investido;

    const response = await fetch('https://api.groq.com/openai/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: process.env.GROQ_MODEL || 'llama-3.1-8b-instant',
        temperature: 0.3,
        max_completion_tokens: 900,
        response_format: { type: 'json_object' },
        messages: [
          {
            role: 'system',
            content: [
              'Voce e o Assistente de Carteira do Marinho Investment.',
              'Analise somente os dados fornecidos pelo aplicativo.',
              'Nao recomende compra, venda, manutencao ou troca de ativos.',
              'Nao use frases normativas como "idealmente", "e recomendavel", "voce deve" ou "melhor ativo".',
              'Nao mande o usuario consultar profissional financeiro; o aviso padrao sera adicionado pelo aplicativo.',
              'Nao faca previsoes de mercado e nao diga qual ativo e melhor.',
              'Nao invente datas, setores, proventos, rentabilidade ou cotacoes ausentes.',
              'Diferencie meta de renda mensal de renda mensal estimada. Meta nao e renda gerada.',
              'Explique concentracao, renda, diferenca entre valor investido e valor atual, e pontos de atencao.',
              'Se houver poucos ativos, diga apenas que a carteira esta concentrada nos ativos cadastrados.',
              'Use portugues do Brasil, linguagem clara, tom profissional e educativo.',
              'Nao use Markdown, negrito, asteriscos, numeracao decorativa ou titulos com simbolos.',
              'Responda somente em JSON valido no formato:',
              '{"resumo":"texto curto","metricas":["item"],"concentracao":["item"],"renda":["item"],"valor_atual":["item"],"pontos_atencao":["item"]}',
              'Cada item deve ter no maximo 160 caracteres.'
            ].join(' ')
          },
          {
            role: 'user',
            content: JSON.stringify({
              meta_renda_mensal: metaRenda,
              totais_calculados_pelo_app: totais,
              carteira: resumo
            })
          }
        ]
      })
    });

    const data = await response.json().catch(() => ({}));
    if (!response.ok) {
      const groqMessage = data?.error?.message || data?.message || 'Falha ao chamar a Groq.';
      return res.status(response.status === 401 ? 401 : 502).json({
        error: 'falha_groq',
        status: response.status,
        message: groqMessage,
        details: data
      });
    }

    const content = data?.choices?.[0]?.message?.content || '{}';
    const analise = JSON.parse(content);
    return res.status(200).json({
      texto: formatarAnalise(analise),
      analise
    });
  } catch (error) {
    return res.status(500).json({
      error: 'falha_assistente',
      message: error.message
    });
  }
};

function formatarAnalise(analise) {
  const secoes = [
    ['Resumo', [analise.resumo]],
    ['Métricas', analise.metricas],
    ['Concentração', analise.concentracao],
    ['Renda', analise.renda],
    ['Valor atual', analise.valor_atual],
    ['Pontos de atenção', analise.pontos_atencao]
  ];

  return secoes
    .map(([titulo, itens]) => {
      const lista = normalizarLista(itens);
      if (!lista.length) return '';
      return `${titulo}\n${lista.map(item => `- ${limparLinguagem(item)}`).join('\n')}`;
    })
    .filter(Boolean)
    .join('\n\n') + '\n\nAviso: análise informativa, não recomendação de investimento.';
}

function normalizarLista(valor) {
  if (!valor) return [];
  return (Array.isArray(valor) ? valor : [valor]).filter(Boolean).map(String);
}

function limparLinguagem(texto) {
  return texto
    .replace(/\*\*/g, '')
    .replace(/\*/g, '')
    .replace(/é recomendável/gi, 'pode ser analisado')
    .replace(/recomenda-se/gi, 'pode ser analisado')
    .replace(/você deve/gi, 'voce pode avaliar')
    .replace(/idealmente/gi, 'em uma leitura de diversificacao')
    .trim();
}

function readJsonBody(req) {
  return new Promise((resolve, reject) => {
    let body = '';
    req.on('data', chunk => {
      body += chunk;
      if (body.length > 100000) {
        req.destroy();
        reject(new Error('payload_muito_grande'));
      }
    });
    req.on('end', () => resolve(body ? JSON.parse(body) : {}));
    req.on('error', reject);
  });
}
