#!/bin/bash
# Script to upload Chapter 1 content to GitHub

echo "===== Kubernetes Architecture Chapter 1 GitHub Upload ====="
echo "This script will help you upload the Chapter 1 content to your GitHub repository."
echo

# Check if git is installed
if ! command -v git &> /dev/null; then
    echo "Error: git is not installed. Please install git first."
    exit 1
fi

# Set the GitHub repository URL
REPO_URL="https://github.com/Salwan-Mohamed/Master_Kubernetes_4thedtion.git"
REPO_NAME="Master_Kubernetes_4thedtion"
CHAPTER_DIR="Chapter1_Understanding_Kubernetes_Architecture"

echo "Step 1: Cloning or updating the repository..."
if [ -d "$REPO_NAME" ]; then
    echo "Repository already exists. Updating..."
    cd "$REPO_NAME"
    git pull
else
    echo "Cloning repository..."
    git clone "$REPO_URL"
    cd "$REPO_NAME"
fi

echo

echo "Step 2: Creating Chapter 1 directory structure..."
mkdir -p "$CHAPTER_DIR"
mkdir -p "$CHAPTER_DIR/images"
mkdir -p "$CHAPTER_DIR/exercises"
mkdir -p "$CHAPTER_DIR/code_examples"

echo

echo "Step 3: Copying content..."
# Assumes this script is run from the parent directory of the Chapter1_Understanding_Kubernetes_Architecture folder
cp -r ../$CHAPTER_DIR/* ./$CHAPTER_DIR/

echo

echo "Step 4: Adding files to git..."
git add ./$CHAPTER_DIR

echo

echo "Step 5: Committing changes..."
git commit -m "Add Chapter 1: Understanding Kubernetes Architecture"

echo

echo "Step 6: Pushing to GitHub..."
git push origin main

echo

echo "===== Upload Complete ====="
echo "The Chapter 1 content has been uploaded to your GitHub repository."
echo "You can view it at: https://github.com/Salwan-Mohamed/Master_Kubernetes_4thedtion"
echo
echo "Next steps:"
echo "1. Verify that all files are correctly uploaded"
echo "2. Check the formatting of the markdown files on GitHub"
echo "3. Continue with Chapter 2 development"
