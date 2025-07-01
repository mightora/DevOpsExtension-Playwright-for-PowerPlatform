<#
    ===========================================================
    Task: Mightora Commit To Git Repository
    
    Originally Created By: Ian Tweedie [https://iantweedie.biz] (Date: 2024-10-08)
    Date: 2024-10-08

    Contributors:
    - Developer A (Contributions: Improved Git configuration handling)
    - Developer B (Contributions: Added support for custom commit messages)
    
    ===========================================================
#>

[CmdletBinding()]

param()

# Import the VSTS Task SDK
Import-Module $PSScriptRoot\ps_modules\VstsTaskSdk\VstsTaskSdk.psd1

# Fetch and display the developer message
function Fetch-DeveloperMessage {
    $url = "https://developer-message.mightora.io/api/HttpTrigger?appname=commitToRepo"
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -ErrorAction Stop
        return $response.message
    } catch {
        return "Developer message not available."
    }
}

# Install Node.js on the target machine
function Install-NodeJS {
    param(
        [string]$NodeVersion = "20.11.1"  # Default to LTS version
    )
    
    Write-Host "Checking if Node.js is already installed..."
    
    # Check if Node.js is already installed
    try {
        $currentVersion = & node --version 2>$null
        if ($currentVersion) {
            Write-Host "Node.js is already installed. Current version: $currentVersion"
            return
        }
    } catch {
        Write-Host "Node.js not found. Proceeding with installation..."
    }
    
    Write-Host "Installing Node.js version $NodeVersion..."
    
    # Determine the architecture
    $arch = if ([Environment]::Is64BitOperatingSystem) { "x64" } else { "x86" }
    
    # Download URL for Node.js Windows installer
    $nodeUrl = "https://nodejs.org/dist/v$NodeVersion/node-v$NodeVersion-win-$arch.zip"
    $downloadPath = "$env:TEMP\node-v$NodeVersion-win-$arch.zip"
    $extractPath = "$env:TEMP\node-v$NodeVersion-win-$arch"
    $installPath = "$env:ProgramFiles\nodejs"
    
    try {
        # Download Node.js
        Write-Host "Downloading Node.js from: $nodeUrl"
        Invoke-WebRequest -Uri $nodeUrl -OutFile $downloadPath -UseBasicParsing
        
        # Extract the ZIP file
        Write-Host "Extracting Node.js to: $extractPath"
        Expand-Archive -Path $downloadPath -DestinationPath $env:TEMP -Force
        
        # Create installation directory if it doesn't exist
        if (!(Test-Path $installPath)) {
            New-Item -Path $installPath -ItemType Directory -Force | Out-Null
        }
        
        # Copy Node.js files to installation directory
        Write-Host "Installing Node.js to: $installPath"
        Copy-Item -Path "$extractPath\*" -Destination $installPath -Recurse -Force
        
        # Add Node.js to PATH for current session
        $env:PATH = "$installPath;$env:PATH"
        
        # Add Node.js to system PATH permanently
        $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        if ($currentPath -notlike "*$installPath*") {
            [Environment]::SetEnvironmentVariable("PATH", "$installPath;$currentPath", "Machine")
            Write-Host "Node.js added to system PATH"
        }
        
        # Verify installation
        $installedVersion = & "$installPath\node.exe" --version
        Write-Host "Node.js successfully installed. Version: $installedVersion"
        Write-Host "npm version: $(& "$installPath\npm.cmd" --version)"
        
        # Clean up temporary files
        Remove-Item -Path $downloadPath -Force -ErrorAction SilentlyContinue
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        
    } catch {
        Write-Error "Failed to install Node.js: $($_.Exception.Message)"
        throw
    }
}

# Clone Playwright repository
function Clone-PlaywrightRepository {
    param(
        [string]$RepositoryUrl = "https://github.com/itweedie/playwrightOnPowerPlatform.git",
        [string]$TargetFolder = "playwright"
    )
    
    Write-Host "Cloning Playwright repository..."
    
    # Get current working directory
    $currentDir = Get-Location
    $playwrightPath = Join-Path $currentDir $TargetFolder
    
    try {
        # Check if git is available
        try {
            $gitVersion = & git --version 2>$null
            Write-Host "Git is available: $gitVersion"
        } catch {
            Write-Error "Git is not installed or not available in PATH. Please install Git first."
            throw "Git not found"
        }
        
        # Remove existing playwright folder if it exists
        if (Test-Path $playwrightPath) {
            Write-Host "Removing existing playwright folder..."
            Remove-Item -Path $playwrightPath -Recurse -Force
        }
        
        # Clone the repository
        Write-Host "Cloning repository from: $RepositoryUrl"
        Write-Host "Target folder: $playwrightPath"
        
        & git clone $RepositoryUrl $playwrightPath
        
        if ($LASTEXITCODE -eq 0) {
            Write-Host "Successfully cloned Playwright repository to: $playwrightPath"
        } else {
            throw "Git clone failed with exit code: $LASTEXITCODE"
        }
        
    } catch {
        Write-Error "Failed to clone Playwright repository: $($_.Exception.Message)"
        throw
    }
}

# Display the developer message
$developerMessage = Fetch-DeveloperMessage
Write-Host "Developer Message: $developerMessage"

# Install Node.js on the target machine
Write-Host "==========================================================="
Write-Host "Installing Node.js..."
Install-NodeJS
Write-Host "==========================================================="

# Clone Playwright repository
Write-Host "==========================================================="
Write-Host "Cloning Playwright repository..."
Clone-PlaywrightRepository
Write-Host "==========================================================="

# Clone the Playwright repository
Write-Host "==========================================================="
Write-Host "Cloning Playwright repository..."
Clone-PlaywrightRepository
Write-Host "==========================================================="


# Output the script information at runtime
Write-Host "==========================================================="
Write-Host "Task: Mightora Commit To Git Repository"
Write-Host "Originally Created By: Ian Tweedie [https://iantweedie.biz] (Date: 2024-10-08)"
Write-Host "Contributors:"
#Write-Host " - Developer A (Contributions: Improved Git configuration handling)"
#Write-Host " - Developer B (Contributions: Added support for custom commit messages)"
Write-Host "==========================================================="

# Get inputs from the task
$commitMsg = Get-VstsInput -Name 'commitMsg'
$branchName = Get-VstsInput -Name 'branchName'
$tags = Get-VstsInput -Name 'tags'

