import React from 'react';

type GYBrandLogoProps = {
  height?: number;
  color?: string;
  className?: string;
  title?: string;
};

/** The compact GY master wordmark from the approved brand specification. */
export const GYBrandLogo: React.FC<GYBrandLogoProps> = ({
  height = 28,
  color = '#111318',
  className = '',
  title = 'GY 输入法',
}) => (
  <svg
    aria-label={title}
    role="img"
    width={height * 1.56}
    height={height}
    viewBox="0 0 156 100"
    fill="none"
    xmlns="http://www.w3.org/2000/svg"
    className={className}
    style={{ shapeRendering: 'geometricPrecision' }}
  >
    <title>{title}</title>
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