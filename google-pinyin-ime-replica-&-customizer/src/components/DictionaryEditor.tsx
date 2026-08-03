import React, { useState } from 'react';
import { Plus, Trash2, BookOpen, Save, RefreshCw } from 'lucide-react';

interface DictionaryEditorProps {
  customDict: Record<string, string[]>;
  onUpdateDict: (newDict: Record<string, string[]>) => void;
}

export const DictionaryEditor: React.FC<DictionaryEditorProps> = ({
  customDict,
  onUpdateDict,
}) => {
  const [newPinyin, setNewPinyin] = useState<string>('');
  const [newCandidates, setNewCandidates] = useState<string>('');

  const handleAddEntry = (e: React.FormEvent) => {
    e.preventDefault();
    const cleanPinyin = newPinyin.toLowerCase().trim();
    const candidatesArr = newCandidates
      .split(/[,，\s]+/)
      .map((s) => s.trim())
      .filter(Boolean);

    if (cleanPinyin && candidatesArr.length > 0) {
      onUpdateDict({
        ...customDict,
        [cleanPinyin]: candidatesArr,
      });
      setNewPinyin('');
      setNewCandidates('');
    }
  };

  const handleDeleteEntry = (key: string) => {
    const copy = { ...customDict };
    delete copy[key];
    onUpdateDict(copy);
  };

  return (
    <div className="bg-white dark:bg-slate-900 border border-slate-200 dark:border-slate-800 rounded-2xl p-5 shadow-xs flex flex-col gap-4">
      <div className="flex items-center justify-between border-b border-slate-100 dark:border-slate-800 pb-3">
        <div className="flex items-center gap-2">
          <BookOpen className="w-5 h-5 text-blue-600 dark:text-blue-400" />
          <h3 className="text-base font-bold text-slate-900 dark:text-slate-100">
            自定义测试词库管理 (Custom Dictionary)
          </h3>
        </div>
      </div>

      {/* Form to Add New Entry */}
      <form onSubmit={handleAddEntry} className="flex flex-col sm:flex-row gap-2">
        <input
          type="text"
          placeholder="拼音 (如 keyle)"
          value={newPinyin}
          onChange={(e) => setNewPinyin(e.target.value)}
          className="px-3 py-2 text-xs border border-slate-200 dark:border-slate-700 rounded-lg bg-slate-50 dark:bg-slate-800 text-slate-900 dark:text-slate-100 font-mono focus:outline-none focus:ring-2 focus:ring-blue-500/50 sm:w-1/3"
        />
        <input
          type="text"
          placeholder="候选词 (用逗号分隔，如: 可以了, 客运量, 可用来)"
          value={newCandidates}
          onChange={(e) => setNewCandidates(e.target.value)}
          className="px-3 py-2 text-xs border border-slate-200 dark:border-slate-700 rounded-lg bg-slate-50 dark:bg-slate-800 text-slate-900 dark:text-slate-100 focus:outline-none focus:ring-2 focus:ring-blue-500/50 flex-1"
        />
        <button
          type="submit"
          className="flex items-center justify-center gap-1.5 bg-blue-600 hover:bg-blue-700 text-white font-semibold text-xs px-4 py-2 rounded-lg transition-colors cursor-pointer shrink-0"
        >
          <Plus className="w-3.5 h-3.5" />
          添加词库词条
        </button>
      </form>

      {/* List of Custom Dict Entries */}
      <div className="flex flex-col gap-2 max-h-48 overflow-y-auto pr-1">
        {Object.keys(customDict).length === 0 ? (
          <div className="text-xs text-slate-400 italic py-2 text-center">
            尚未添加自定义词条（系统正使用内置常用词库）
          </div>
        ) : (
          (Object.entries(customDict) as [string, string[]][]).map(([pinyinKey, wordList]) => (
            <div
              key={pinyinKey}
              className="flex items-center justify-between p-2.5 rounded-xl bg-slate-50 dark:bg-slate-800/60 border border-slate-100 dark:border-slate-800 text-xs"
            >
              <div className="flex items-center gap-3">
                <span className="font-mono font-bold text-blue-600 dark:text-blue-400 shrink-0">
                  {pinyinKey}
                </span>
                <div className="flex items-center gap-1.5 flex-wrap">
                  {wordList.map((w, idx) => (
                    <span
                      key={idx}
                      className="bg-white dark:bg-slate-700 px-2 py-0.5 rounded text-slate-800 dark:text-slate-200 border border-slate-200 dark:border-slate-600 text-[11px]"
                    >
                      <span className="text-slate-400 mr-1">{idx + 1}</span>
                      {w}
                    </span>
                  ))}
                </div>
              </div>
              <button
                onClick={() => handleDeleteEntry(pinyinKey)}
                className="p-1.5 text-slate-400 hover:text-rose-600 transition-colors cursor-pointer"
                title="删除"
              >
                <Trash2 className="w-3.5 h-3.5" />
              </button>
            </div>
          ))
        )}
      </div>
    </div>
  );
};
