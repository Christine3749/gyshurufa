import React from 'react';

interface GYWordmarkLogoProps {
  size?: number | 'sm' | 'md' | 'lg' | 'xl';
  color?: string;
  showSubtitle?: boolean;
  className?: string;
}

/**
 * GY 输入法 - 官方标准字标 (GY Compact Master Wordmark)
 * 
 * 1. 紧凑的“GY”大写拉丁字母，字距收紧 20%，视觉形成整体
 * 2. 现代标准无衬线粗体骨架
 * 3. 无渐变、无装饰、无外框，纯粹精细
 */
export const GYWordmarkLogo: React.FC<GYWordmarkLogoProps> = ({
  size = 'lg',
  color = '#111318',
  showSubtitle = true,
  className = '',
}) => {
  const heightMap = {
    sm: 28,
    md: 48,
    lg: 80,
    xl: 120,
  };

  const currentHeight = typeof size === 'number' ? size : heightMap[size];
  // 收紧字距后 viewBox 调整为 156 x 100，宽高比 1.56
  const currentWidth = currentHeight * 1.56;

  return (
    <div className={`inline-flex flex-col items-center justify-center select-none ${className}`}>
      <svg
        width={currentWidth}
        height={currentHeight}
        viewBox="0 0 156 100"
        fill="none"
        xmlns="http://www.w3.org/2000/svg"
        className="transition-colors duration-200"
        style={{ shapeRendering: 'geometricPrecision' }}
      >
        {/* 字母 G (Standard Capital G) */}
        <path
          d="M 72 26 
             C 65 18, 54 13, 40 13 
             C 21 13, 8 28, 8 50 
             C 8 72, 21 87, 40 87 
             C 56 87, 68 77, 72 63 
             L 72 52 
             L 40 52 
             L 40 66 
             L 57 66 
             C 54 72, 48 74, 40 74 
             C 28 74, 21 64, 21 50 
             C 21 36, 28 26, 40 26 
             C 49 26, 56 31, 60 37 
             L 72 26 Z"
          fill={color}
        />

        {/* 字母 Y (Standard Capital Y - 收紧字距 X offset -18) */}
        <path
          d="M 80 15 
             L 94 15 
             L 114 50 
             L 134 15 
             L 148 15 
             L 121 60 
             L 121 87 
             L 107 87 
             L 107 60 
             L 80 15 Z"
          fill={color}
        />
      </svg>

      {/* 官网字标副标题：输入法 */}
      {showSubtitle && (
        <div
          className="font-sans font-medium tracking-[0.32em] text-center uppercase transition-colors"
          style={{
            color,
            fontSize: Math.max(12, currentHeight * 0.2),
            marginTop: Math.max(6, currentHeight * 0.12),
            opacity: 0.85,
          }}
        >
          输入法
        </div>
      )}
    </div>
  );
};

/**
 * 纯 GY 字母 SVG 路径（用于系统小尺寸图标及各种容器组合）
 */
export const GYSymbolPathSVG: React.FC<{
  size?: number;
  color?: string;
}> = ({ size = 32, color = '#FFFFFF' }) => {
  return (
    <svg
      width={size * 1.56}
      height={size}
      viewBox="0 0 156 100"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      style={{ shapeRendering: 'geometricPrecision' }}
    >
      <path
        d="M 72 26 C 65 18, 54 13, 40 13 C 21 13, 8 28, 8 50 C 8 72, 21 87, 40 87 C 56 87, 68 77, 72 63 L 72 52 L 40 52 L 40 66 L 57 66 C 54 72, 48 74, 40 74 C 28 74, 21 64, 21 50 C 21 36, 28 26, 40 26 C 49 26, 56 31, 60 37 L 72 26 Z"
        fill={color}
      />
      <path
        d="M 80 15 L 94 15 L 114 50 L 134 15 L 148 15 L 121 60 L 121 87 L 107 87 L 107 60 L 80 15 Z"
        fill={color}
      />
    </svg>
  );
};

/**
 * 系统图标规格 (16px, 24px, 32px 系统级小图标)
 * 规则：白色 GY 字母，深墨黑背景 (#111318)
 */
export const GYSystemAppIcon: React.FC<{
  size: 16 | 24 | 32 | 48 | 64;
  borderRadius?: number;
}> = ({ size, borderRadius }) => {
  // 比例换算
  const fontHeight = size * 0.52;
  const radius = borderRadius !== undefined ? borderRadius : Math.round(size * 0.22);

  return (
    <div
      style={{
        width: size,
        height: size,
        backgroundColor: '#111318',
        borderRadius: radius,
      }}
      className="inline-flex items-center justify-center shrink-0 shadow-xs select-none"
    >
      <GYSymbolPathSVG size={fontHeight} color="#FFFFFF" />
    </div>
  );
};
