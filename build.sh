#!/bin/bash

# SimpleSimulatorManager Build Script
# This script builds and signs the app for distribution

set -e  # Exit on any error

echo "🚀 Building SimpleSimulatorManager..."
echo "=================================="

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "❌ Error: .env file not found!"
    echo "Create .env in the repository root and fill in your signing variables."
    exit 1
fi

# Install dependencies if needed
if [ ! -f "Gemfile.lock" ]; then
    echo "📦 Installing Ruby dependencies..."
    bundle install
fi

# Run the build
echo "🔨 Building app..."
bundle exec fastlane release

echo ""
echo "✅ Build completed successfully!"
echo ""
echo "📁 Files created in ./release/:"
echo "   - SimulatorManager.zip (for GitHub releases)"
echo ""
echo "🎉 Ready to upload to GitHub releases!"
