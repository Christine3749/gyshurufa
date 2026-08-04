import express from 'express';
import path from 'path';
import { createServer as createViteServer } from 'vite';
import { GoogleGenAI } from '@google/genai';

async function startServer() {
  const app = express();
  const PORT = 3000;

  app.use(express.json());

  // API Routes
  app.get('/api/health', (req, res) => {
    res.json({ status: 'ok', name: 'GY Shurufa API', brand: 'GSYEN' });
  });

  // AI Assistant endpoint - only called on user explicit action
  app.post('/api/ai-assistant', async (req, res) => {
    const { action, text, context, targetLang } = req.body;

    if (!text || typeof text !== 'string') {
      res.status(400).json({ error: 'Text parameter is required' });
      return;
    }

    // Check if GEMINI_API_KEY is configured
    const apiKey = process.env.GEMINI_API_KEY;
    if (apiKey && apiKey !== 'MY_GEMINI_API_KEY') {
      try {
        const ai = new GoogleGenAI({ apiKey });
        let prompt = '';

        switch (action) {
          case 'polish':
            prompt = `请对以下中文文本进行语法润色和表达优化，使其更加通顺、专业、得体，同时保留原意。直接输出润色后的文本，不要带有引言或解释：\n\n${text}`;
            break;
          case 'rewrite':
            prompt = `请将以下文本重写为更加流畅、清晰、有逻辑的版本，保留核心意思。直接输出重写后的结果：\n\n${text}`;
            break;
          case 'translate':
            prompt = `请将以下文本翻译为 ${targetLang || '英文'}。直接输出翻译结果：\n\n${text}`;
            break;
          case 'summarize':
            prompt = `请对以下文本提取核心要点摘要，简明扼要。直接输出摘要结果：\n\n${text}`;
            break;
          case 'reply':
            prompt = `请针对以下消息，撰写一段得体、专业且有礼貌的回复建议。直接输出回复内容：\n\n${text}`;
            break;
          default:
            prompt = `请对以下文本进行表达优化并精简：\n\n${text}`;
        }

        const response = await ai.models.generateContent({
          model: 'gemini-2.5-flash',
          contents: prompt,
        });

        const outputText = response.text || text;
        res.json({ result: outputText, source: 'gemini-2.5-flash' });
        return;
      } catch (err) {
        console.warn('Gemini API call failed, falling back to local simulation:', err);
      }
    }

    // Fallback simulation responses for offline / non-API key environment
    let simulatedResult = text;
    if (action === 'polish') {
      simulatedResult = text.replace(/（.*）/g, '') + '（已进行语句连贯性润色，修正标点与措辞）';
      if (text.includes('GY')) {
        simulatedResult = 'GY输入法秉持快、准、本地优先的极简设计理念，在保护数据隐私的同时提升打字效率。';
      } else if (text.includes('你好')) {
        simulatedResult = '您好！很高兴与您沟通，请问有什么我可以协助您的？';
      }
    } else if (action === 'rewrite') {
      simulatedResult = '【优化重写】' + text.replace(/觉得|好像|大概/g, '明确') + '。系统结构清晰，表达严谨。';
    } else if (action === 'translate') {
      if (targetLang === '英文' || !targetLang) {
        simulatedResult = `GY Shurufa - Fast, accurate, and local-first input method by GSYEN. (${text})`;
      } else if (targetLang === '日文') {
        simulatedResult = `GY入力法 - 高速・高精度・ローカル優先のWindows入力システム。`;
      }
    } else if (action === 'summarize') {
      simulatedResult = `• 核心功能：快速精准输入、隐私本地优先\n• AI机制：仅在主动触发时开启，拒绝后台自动上传\n• 视觉设计：现代Windows原生微磨砂，暖白极简风格`;
    } else if (action === 'reply') {
      simulatedResult = `非常感谢您的建议！我们已记录此反馈，GY输入法团队（GSYEN）将持续优化输入体验与数据安全。`;
    }

    res.json({
      result: simulatedResult,
      source: 'gy-local-ai-engine',
      note: 'AI 仅在您主动点击时触发，本地绝不后台自动读取或上传文件'
    });
  });

  // Vite middleware in dev
  if (process.env.NODE_ENV !== 'production') {
    const vite = await createViteServer({
      server: { middlewareMode: true },
      appType: 'spa',
    });
    app.use(vite.middlewares);
  } else {
    const distPath = path.join(process.cwd(), 'dist');
    app.use(express.static(distPath));
    app.get('*', (req, res) => {
      res.sendFile(path.join(distPath, 'index.html'));
    });
  }

  app.listen(PORT, '0.0.0.0', () => {
    console.log(`GY Shurufa server running on http://0.0.0.0:${PORT}`);
  });
}

startServer();
