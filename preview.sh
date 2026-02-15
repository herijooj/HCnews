#!/usr/bin/env bash
set -e

# Ensure we are in the script directory
cd "$(dirname "$0")"

echo "🏗️  Building daily content..."
# Run the build script
./build_daily.sh

echo "📄 Generating HTML files..."
mkdir -p public
DATE=$(date +'%d/%m/%Y')

# Generate Tudo (index.html)
sed "s|{{DATE}}|$DATE|g" .github/template.html |
	sed -e '/{{CONTENT}}/r public/news_tudo.out' -e '/{{CONTENT}}/d' >public/index.html
echo "   - public/index.html"

# Generate Notícias (noticias.html)
sed "s|{{DATE}}|$DATE|g" .github/template.html |
	sed -e '/{{CONTENT}}/r public/news_noticias.out' -e '/{{CONTENT}}/d' >public/noticias.html
echo "   - public/noticias.html"

# Generate Horóscopo (horoscopo.html)
sed "s|{{DATE}}|$DATE|g" .github/template.html |
	sed -e '/{{CONTENT}}/r public/news_horoscopo.out' -e '/{{CONTENT}}/d' >public/horoscopo.html
echo "   - public/horoscopo.html"

# Generate Futebol (esportes.html)
sed "s|{{DATE}}|$DATE|g" .github/template.html |
	sed -e '/{{CONTENT}}/r public/news_esportes.out' -e '/{{CONTENT}}/d' >public/esportes.html
echo "   - public/esportes.html"

# Generate Previsão do Tempo (weather.html)
sed "s|{{DATE}}|$DATE|g" .github/template.html |
	sed -e '/{{CONTENT}}/r public/news_weather.out' -e '/{{CONTENT}}/d' >public/weather.html
echo "   - public/weather.html"

# Generate Hacker News (hackernews.html)
sed "s|{{DATE}}|$DATE|g" .github/template.html |
	sed -e '/{{CONTENT}}/r public/news_hackernews.out' -e '/{{CONTENT}}/d' >public/hackernews.html
echo "   - public/hackernews.html"

echo "✅ Build complete!"
echo ""
echo "🚀 Starting preview server at http://0.0.0.0:8000"
echo "   (Open your browser to this URL to view the site)"
echo "   Press Ctrl+C to stop."
echo ""

cd public
python3 -m http.server 8000
