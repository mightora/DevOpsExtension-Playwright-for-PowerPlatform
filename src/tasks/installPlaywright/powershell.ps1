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

# Install Playwright from the cloned repository
function Install-PlaywrightFromRepository {
    param(
        [string]$PlaywrightFolder = "playwright"
    )
    
    Write-Host "Installing Playwright from repository..."
    
    # Get the playwright folder path
    $currentDir = Get-Location
    $playwrightPath = Join-Path $currentDir $PlaywrightFolder
    
    try {
        # Check if the playwright folder exists
        if (!(Test-Path $playwrightPath)) {
            throw "Playwright folder not found at: $playwrightPath"
        }
        
        # Change to the playwright directory
        Write-Host "Changing to playwright directory: $playwrightPath"
        Push-Location $playwrightPath
        
        # Check if package.json exists
        if (!(Test-Path "package.json")) {
            throw "package.json not found in the playwright directory"
        }
        
        # Install npm dependencies
        Write-Host "Installing npm dependencies..."
        & npm install
        
        if ($LASTEXITCODE -ne 0) {
            throw "npm install failed with exit code: $LASTEXITCODE"
        }
        
        Write-Host "npm dependencies installed successfully"
        
        # Install Playwright browsers
        Write-Host "Installing Playwright browsers..."
        & npx playwright install
        
        if ($LASTEXITCODE -ne 0) {
            throw "Playwright browser installation failed with exit code: $LASTEXITCODE"
        }
        
        Write-Host "Playwright browsers installed successfully"
        
        # Optional: Install Playwright dependencies for specific OS
        Write-Host "Installing Playwright system dependencies..."
        & npx playwright install-deps
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Playwright system dependencies installation completed with warnings (exit code: $LASTEXITCODE)"
        } else {
            Write-Host "Playwright system dependencies installed successfully"
        }
        
        Write-Host "Playwright installation completed successfully"
        
    } catch {
        Write-Error "Failed to install Playwright: $($_.Exception.Message)"
        throw
    } finally {
        # Return to the original directory
        Pop-Location
    }
}

# Copy tests from specified location to playwright tests folder
function Copy-TestsToPlaywright {
    param(
        [string]$TestLocation,
        [string]$PlaywrightFolder = "playwright"
    )
    
    Write-Host "Copying tests from specified location to Playwright tests folder..."
    
    # Get the current directory and playwright path  
    $currentDir = Get-Location
    $playwrightPath = Join-Path $currentDir $PlaywrightFolder
    $playwrightTestsPath = Join-Path $playwrightPath "tests"
    
    try {
        # Validate test location
        if ([string]::IsNullOrWhiteSpace($TestLocation)) {
            Write-Warning "No test location specified. Skipping test copy operation."
            return
        }
        
        # Check if the test location exists
        if (!(Test-Path $TestLocation)) {
            throw "Test location not found: $TestLocation"
        }
        
        # Check if playwright folder exists
        if (!(Test-Path $playwrightPath)) {
            throw "Playwright folder not found at: $playwrightPath"
        }
        
        # Create tests directory if it doesn't exist
        if (!(Test-Path $playwrightTestsPath)) {
            Write-Host "Creating tests directory: $playwrightTestsPath"
            New-Item -Path $playwrightTestsPath -ItemType Directory -Force | Out-Null
        }
        
        # Get all test files from the source location
        Write-Host "Source test location: $TestLocation"
        Write-Host "Destination tests folder: $playwrightTestsPath"
        
        # Copy all files from test location to playwright tests folder
        $testFiles = Get-ChildItem -Path $TestLocation -Recurse -File
        
        if ($testFiles.Count -eq 0) {
            Write-Warning "No test files found in the specified location: $TestLocation"
            return
        }
        
        Write-Host "Found $($testFiles.Count) test files to copy"
        
        foreach ($file in $testFiles) {
            # Calculate relative path to maintain directory structure
            $relativePath = $file.FullName.Substring($TestLocation.Length).TrimStart('\', '/')
            $destinationPath = Join-Path $playwrightTestsPath $relativePath
            $destinationDir = Split-Path $destinationPath -Parent
            
            # Create destination directory if it doesn't exist
            if (!(Test-Path $destinationDir)) {
                New-Item -Path $destinationDir -ItemType Directory -Force | Out-Null
            }
            
            # Copy the file
            Copy-Item -Path $file.FullName -Destination $destinationPath -Force
            Write-Host "Copied: $($file.Name) -> $relativePath"
        }
        
        Write-Host "Successfully copied $($testFiles.Count) test files to Playwright tests folder"
        
    } catch {
        Write-Error "Failed to copy tests to Playwright folder: $($_.Exception.Message)"
        throw
    }
}

# Run Playwright tests
function Run-PlaywrightTests {
    param(
        [string]$PlaywrightFolder = "playwright",
        [string]$TestPattern = "",
        [string]$Browser = "chromium",
        [switch]$Headless = $true
    )
    
    Write-Host "Running Playwright tests..."
    
    # Get the playwright folder path
    $currentDir = Get-Location
    $playwrightPath = Join-Path $currentDir $PlaywrightFolder
    
    try {
        # Check if playwright folder exists
        if (!(Test-Path $playwrightPath)) {
            throw "Playwright folder not found at: $playwrightPath"
        }
        
        # Change to the playwright directory
        Write-Host "Changing to playwright directory: $playwrightPath"
        Push-Location $playwrightPath
        
        # Check if tests directory exists
        $testsPath = Join-Path $playwrightPath "tests"
        if (!(Test-Path $testsPath)) {
            Write-Warning "No tests directory found at: $testsPath"
            Write-Host "Skipping test execution."
            return
        }
        
        # Count test files
        $testFiles = Get-ChildItem -Path $testsPath -Recurse -File -Include "*.spec.js", "*.spec.ts", "*.test.js", "*.test.ts"
        Write-Host "Found $($testFiles.Count) test files to execute"
        
        if ($testFiles.Count -eq 0) {
            Write-Warning "No Playwright test files found in the tests directory"
            return
        }
        
        # Build the test command
        $testCommand = "npx playwright test"
        
        # Add browser specification if provided
        if (![string]::IsNullOrWhiteSpace($Browser)) {
            $testCommand += " --project=$Browser"
        }
        
        # Add headless mode
        if ($Headless) {
            $testCommand += " --headed=false"
        } else {
            $testCommand += " --headed=true"
        }
        
        # Add test pattern if specified
        if (![string]::IsNullOrWhiteSpace($TestPattern)) {
            $testCommand += " $TestPattern"
        }
        
        # Add reporter for better output in CI/CD
        $testCommand += " --reporter=list,json"
        
        Write-Host "Executing command: $testCommand"
        Write-Host "Starting Playwright test execution..."
        
        # Execute the tests
        Invoke-Expression $testCommand
        
        $testExitCode = $LASTEXITCODE
        
        if ($testExitCode -eq 0) {
            Write-Host "All Playwright tests passed successfully!" -ForegroundColor Green
        } else {
            Write-Warning "Some Playwright tests failed or encountered issues (Exit Code: $testExitCode)"
            
            # Check if test results exist
            $resultsPath = Join-Path $playwrightPath "test-results"
            if (Test-Path $resultsPath) {
                Write-Host "Test results available at: $resultsPath"
            }
            
            # Check if HTML report exists
            $reportPath = Join-Path $playwrightPath "playwright-report"
            if (Test-Path $reportPath) {
                Write-Host "HTML report available at: $reportPath"
            }
        }
        
        # Return the exit code for pipeline decision making
        return $testExitCode
        
    } catch {
        Write-Error "Failed to run Playwright tests: $($_.Exception.Message)"
        throw
    } finally {
        # Return to the original directory
        Pop-Location
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

# Install Playwright from the cloned repository
Write-Host "==========================================================="
Write-Host "Installing Playwright from repository..."
Install-PlaywrightFromRepository
Write-Host "==========================================================="

# Copy tests from specified location to playwright tests folder
Write-Host "==========================================================="
Write-Host "Copying tests to Playwright tests folder..."
Copy-TestsToPlaywright -TestLocation $testLocation
Write-Host "==========================================================="

# Run Playwright tests
Write-Host "==========================================================="
Write-Host "Running Playwright tests..."
$testResults = Run-PlaywrightTests
Write-Host "==========================================================="

# Run Playwright tests
Write-Host "==========================================================="
Write-Host "Running Playwright tests..."
Run-PlaywrightTests -PlaywrightFolder "playwright" -TestPattern "**/*.spec.js" -Browser "chromium" -Headless $true
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
$testLocation = Get-VstsInput -Name 'testLocation'
$branchName = Get-VstsInput -Name 'branchName'
$tags = Get-VstsInput -Name 'tags'

