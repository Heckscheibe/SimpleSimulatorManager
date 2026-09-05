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

# Fail fast on the wrong Ruby: a mismatch otherwise surfaces as an obscure gem
# error partway through signing or notarization.
REQUIRED_RUBY="$(cat .ruby-version)"
if ! command -v ruby >/dev/null 2>&1; then
    echo "❌ Error: no ruby on PATH. This project requires Ruby $REQUIRED_RUBY."
    echo "   See FASTLANE_README.md for setup instructions."
    exit 1
fi
ACTIVE_RUBY="$(ruby -e 'print RUBY_VERSION')"
if [ "$ACTIVE_RUBY" != "$REQUIRED_RUBY" ]; then
    echo "❌ Error: this project requires Ruby $REQUIRED_RUBY, but Ruby $ACTIVE_RUBY is active."
    echo "   Install it with your version manager (rbenv/rvm/mise/asdf) or Homebrew,"
    echo "   then re-run from a shell where .ruby-version has been picked up."
    echo "   See FASTLANE_README.md for setup instructions."
    exit 1
fi

# Install dependencies if the bundle is missing or out of date
if ! bundle check >/dev/null 2>&1; then
    echo "📦 Installing Ruby dependencies..."
    bundle install
fi

# Run the build
echo "🔨 Building app..."
bundle exec fastlane release

echo ""
echo "✅ Build and notarization completed successfully!"
echo ""
echo "📁 Files created in ./release/:"
echo "   - SimulatorManager.zip (notarized, for GitHub releases)"
echo ""
echo "🎉 Ready to upload to GitHub releases!"
