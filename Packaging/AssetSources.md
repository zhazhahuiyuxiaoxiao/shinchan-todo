# 应用图标来源

- 日期：2026-10-10（Asia/Shanghai）。
- 用户确认样式：奶油色底、小新头像配红色勾选标记。
- 生成方式：OpenAI 内置 imagegen；随后使用同一工具调整透明边缘。
- 项目源图：AppIcon.png，1254 × 1254，PNG alpha 透明通道。
- sips 和 iconutil 仅做图标尺寸转换与 macOS 容器打包，不修改图案。
- 原角色知识产权归权利人，此记录不是商业授权；没有运行时图片请求。

## 初始生成提示词

Use case: logo-design. Create one production-ready macOS application icon for a personal todo app named 小新待办. Square 1024 x 1024 canvas. A large warm cream (#FFF8E7) rounded-square tile with transparent outer corners and small even transparent margins. Center a cheerful recognizable Crayon Shin-chan (Shinnosuke Nohara) head and a little red shirt, thick black eyebrows, simple black eyes, blushing cheeks, playful friendly expression. The face is the dominant shape and remains readable at 32px; no scenery, no laptop, no plants, no tiny decorations. Add a bold red (#CE3B3B) circular completion badge with a white checkmark near the lower right, overlapping the shoulder area but not the face. Clean simplified hand-drawn cartoon line art with thick dark (#20212B) contours, warm cream, red and yellow palette, subtle crayon texture only, no 3D. Crisp silhouette, a professionally composed native Mac app icon, not a screenshot or app mockup. No text, no lettering, no watermark. Actual alpha transparency outside the cream rounded-square tile, preserve its cream interior.

## 透明边缘调整提示词

Use case: precise-object-edit. This is the final macOS app icon. Preserve the Shin-chan character face, expression, thick eyebrows, red shirt, red completion badge and white checkmark, cream background tile, composition, and crayon texture inside the tile exactly. Change ONLY the exterior perimeter: ensure the cream rounded-square tile has an even crisp smooth clean outer silhouette, with a small even transparent margin all around. Remove EVERY stray isolated white pixel, white brush fleck, disconnected crayon fragment or noise outside that silhouette. The exterior of the rounded-square must be 100% alpha transparent. No cast shadow, no fringe, no solid black background. Keep the cream interior opaque. Keep it square, no text, no watermark.
