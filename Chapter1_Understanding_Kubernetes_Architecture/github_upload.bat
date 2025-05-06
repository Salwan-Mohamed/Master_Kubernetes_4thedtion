@echo off
REM Script to upload Chapter 1 content to GitHub for Windows users

echo ===== Kubernetes Architecture Chapter 1 GitHub Upload =====
echo This script will help you upload the Chapter 1 content to your GitHub repository.
echo.

REM Check if git is installed
where git >nul 2>nul
if %ERRORLEVEL% neq 0 (
    echo Error: git is not installed. Please install git first.
    exit /b 1
)

REM Set the GitHub repository URL
set REPO_URL=https://github.com/Salwan-Mohamed/Master_Kubernetes_4thedtion.git
set REPO_NAME=Master_Kubernetes_4thedtion
set CHAPTER_DIR=Chapter1_Understanding_Kubernetes_Architecture

echo Step 1: Cloning or updating the repository...
if exist "%REPO_NAME%" (
    echo Repository already exists. Updating...
    cd "%REPO_NAME%"
    git pull
) else (
    echo Cloning repository...
    git clone "%REPO_URL%"
    cd "%REPO_NAME%"
)

echo.

echo Step 2: Creating Chapter 1 directory structure...
if not exist "%CHAPTER_DIR%" mkdir "%CHAPTER_DIR%"
if not exist "%CHAPTER_DIR%\images" mkdir "%CHAPTER_DIR%\images"
if not exist "%CHAPTER_DIR%\exercises" mkdir "%CHAPTER_DIR%\exercises"
if not exist "%CHAPTER_DIR%\code_examples" mkdir "%CHAPTER_DIR%\code_examples"

echo.

echo Step 3: Copying content...
xcopy /E /Y "..\%CHAPTER_DIR%\*" ".\%CHAPTER_DIR%\"

echo.

echo Step 4: Adding files to git...
git add ".\%CHAPTER_DIR%"

echo.

echo Step 5: Committing changes...
git commit -m "Add Chapter 1: Understanding Kubernetes Architecture"

echo.

echo Step 6: Pushing to GitHub...
git push origin main

echo.

echo ===== Upload Complete =====
echo The Chapter 1 content has been uploaded to your GitHub repository.
echo You can view it at: https://github.com/Salwan-Mohamed/Master_Kubernetes_4thedtion
echo.
echo Next steps:
echo 1. Verify that all files are correctly uploaded
echo 2. Check the formatting of the markdown files on GitHub
echo 3. Continue with Chapter 2 development

pause
