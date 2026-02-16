#!/usr/bin/env bash
set -e

# Ensure we are in the script directory
cd "$(dirname "$0")"

echo "🏗️  Building daily content..."
# Run the build script
./build_daily.sh

echo "📄 Generating HTML files..."
bash scripts/generate_html.sh

echo "✅ Build complete!"
echo ""
echo "🚀 Starting preview server at http://0.0.0.0:8000"
echo "   (Open your browser to this URL to view the site)"
echo "   Press Ctrl+C to stop."
echo ""

cd public
python3 -m http.server 8000
