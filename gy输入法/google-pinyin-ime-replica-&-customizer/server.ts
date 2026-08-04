import express from 'express';
import path from 'path';
import { fileURLToPath } from 'url';
import { GoogleGenAI } from '@google/genai';
import dotenv from 'dotenv';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const app = express();
const PORT = 3000;

app.use(express.json());

// Initialize Gemini Client safely
let aiClient: GoogleGenAI | null = null;
function getGeminiClient(): GoogleGenAI | null {
  if (!aiClient && process.env.GEMINI_API_KEY) {
    try {
      aiClient = new GoogleGenAI({ apiKey: process.env.GEMINI_API_KEY });
    } catch (e) {
      console.error('Failed to initialize Gemini AI client:', e);
    }
  }
  return aiClient;
}

// API Endpoint for AI-powered Pinyin candidate lookup
app.post('/api/pinyin-ai', async (req, res) => {
  const { pinyin, count = 5 } = req.body;

  if (!pinyin || typeof pinyin !== 'string') {
    return res.status(400).json({ error: 'Pinyin string is required' });
  }

  const ai = getGeminiClient();
  if (!ai) {
    // Return fallback info if Gemini API key is not configured
    return res.json({
      candidates: null,
      message: 'GEMINI_API_KEY not configured. Using built-in dictionary.',
    });
  }

  try {
    const prompt = `You are a high-speed Chinese IME (Input Method Engine) language model like Google Pinyin.
Given the pinyin sequence "${pinyin.toLowerCase()}", generate exactly ${count} most likely, natural Simplified Chinese candidates (words or short phrases) ordered by frequency/probability.
Return ONLY a valid JSON array of strings without markdown formatting. Example output: ["第一个", "第二个", "第三个"]`;

    const response = await ai.models.generateContent({
      model: 'gemini-2.5-flash',
      contents: prompt,
    });

    const text = response.text?.trim() || '';
    // Parse JSON array from response
    const cleanJson = text.replace(/```json|```/g, '').trim();
    const candidates = JSON.parse(cleanJson);

    if (Array.isArray(candidates) && candidates.length > 0) {
      return res.json({ candidates });
    } else {
      return res.json({ candidates: null, message: 'Invalid AI output format' });
    }
  } catch (err: any) {
    console.error('Gemini Pinyin Error:', err);
    return res.status(500).json({ error: 'AI generation failed', details: err.message });
  }
});

async function startServer() {
  if (process.env.NODE_ENV !== 'production') {
    const { createServer: createViteServer } = await import('vite');
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
    console.log(`Server running on http://0.0.0.0:${PORT}`);
  });
}

startServer();
