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

# Helper function to safely create directories
function New-DirectoryIfNotExists {
    param(
        [string]$Path,
        [string]$Description = "directory"
    )
    
    if (![string]::IsNullOrWhiteSpace($Path) -and !(Test-Path $Path)) {
        try {
            Write-Host "Creating $Description at: $Path"
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            Write-Host "Successfully created $Description"
            return $true
        } catch {
            Write-Error "Failed to create $Description at $Path. Error: $($_.Exception.Message)"
            return $false
        }
    }
    return $true
}

# Fetch and display the developer message
function Fetch-DeveloperMessage {
    $url = "https://developer-message.mightora.io/api/HttpTrigger?appname=playwrightForPowerPlatform"
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
        [string]$TargetFolder = "playwright",
        [string]$Branch = ""  # Optional branch/tag/commit to clone
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
        
        if (![string]::IsNullOrWhiteSpace($Branch)) {
            Write-Host "Cloning specific branch/tag/commit: $Branch"
            & git clone --branch $Branch $RepositoryUrl $playwrightPath
        } else {
            Write-Host "Cloning default branch"
            & git clone $RepositoryUrl $playwrightPath
        }
        
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
        [string]$PlaywrightFolder = "playwright",
        [string]$TargetBrowser = "chromium"
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
        
        # Set browser environment variable for the installation process
        $env:PLAYWRIGHT_BROWSER = $TargetBrowser
        Write-Host "Target browser set to: $TargetBrowser"
        
        # Install npm dependencies with cache optimization
        Write-Host "Installing npm dependencies..."
        
        # Use Start-Process for more reliable npm execution
        try {
            Write-Host "Executing: npm ci --prefer-offline --no-audit --no-fund"
            $npmCiProcess = Start-Process -FilePath "npm" -ArgumentList "ci", "--prefer-offline", "--no-audit", "--no-fund" -Wait -PassThru -NoNewWindow
            $npmCiExitCode = $npmCiProcess.ExitCode
        } catch {
            Write-Warning "Failed to execute npm ci: $($_.Exception.Message)"
            $npmCiExitCode = 1
        }
        
        if ($npmCiExitCode -ne 0) {
            Write-Warning "npm ci failed (exit code: $npmCiExitCode), falling back to npm install..."
            try {
                Write-Host "Executing: npm install --prefer-offline --no-audit --no-fund"
                $npmInstallProcess = Start-Process -FilePath "npm" -ArgumentList "install", "--prefer-offline", "--no-audit", "--no-fund" -Wait -PassThru -NoNewWindow
                $npmInstallExitCode = $npmInstallProcess.ExitCode
                
                if ($npmInstallExitCode -ne 0) {
                    throw "npm install failed with exit code: $npmInstallExitCode"
                }
            } catch {
                Write-Error "Failed to execute npm install: $($_.Exception.Message)"
                throw "npm install failed with exit code: $npmInstallExitCode"
            }
        }
        
        Write-Host "npm dependencies installed successfully"
        
        # Install Playwright browsers - optimized for specific browser only
        Write-Host "Installing Playwright browsers (optimized for target browser only)..."
        
        # Get browser from environment or default to chromium
        $targetBrowser = if ($env:PLAYWRIGHT_BROWSER) { $env:PLAYWRIGHT_BROWSER } else { "chromium" }
        
        Write-Host "Installing only $targetBrowser browser for faster execution..."
        
        try {
            Write-Host "Executing: npx playwright install $targetBrowser"
            $playwrightInstallProcess = Start-Process -FilePath "npx" -ArgumentList "playwright", "install", $targetBrowser -Wait -PassThru -NoNewWindow
            $playwrightInstallExitCode = $playwrightInstallProcess.ExitCode
        } catch {
            Write-Error "Failed to execute npx playwright install: $($_.Exception.Message)"
            throw "Playwright browser installation failed"
        }
        
        if ($playwrightInstallExitCode -ne 0) {
            throw "Playwright browser installation failed with exit code: $playwrightInstallExitCode"
        }
        
        Write-Host "Playwright browsers installed successfully"
        
        # Install only system dependencies for the specific browser (much faster)
        Write-Host "Installing Playwright system dependencies for $targetBrowser..."
        
        try {
            Write-Host "Executing: npx playwright install-deps $targetBrowser"
            $playwrightDepsProcess = Start-Process -FilePath "npx" -ArgumentList "playwright", "install-deps", $targetBrowser -Wait -PassThru -NoNewWindow
            $playwrightDepsExitCode = $playwrightDepsProcess.ExitCode
        } catch {
            Write-Warning "Failed to execute npx playwright install-deps: $($_.Exception.Message)"
            $playwrightDepsExitCode = 1
        }
        
        if ($playwrightDepsExitCode -ne 0) {
            Write-Warning "Playwright system dependencies installation completed with warnings (exit code: $playwrightDepsExitCode)"
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
            Write-Warning "Test location not found: $TestLocation"
            Write-Host "Attempting to create test location directory..."
            try {
                New-Item -Path $TestLocation -ItemType Directory -Force | Out-Null
                Write-Host "Created test location directory: $TestLocation"
                Write-Warning "Directory was empty, no tests to copy."
                return
            } catch {
                throw "Test location not found and could not be created: $TestLocation. Error: $($_.Exception.Message)"
            }
        }
        
        # Check if playwright folder exists
        if (!(Test-Path $playwrightPath)) {
            throw "Playwright folder not found at: $playwrightPath"
        }
        
        # Create tests directory if it doesn't exist
        if (!(Test-Path $playwrightTestsPath)) {
            if (!(New-DirectoryIfNotExists -Path $playwrightTestsPath -Description "tests directory")) {
                throw "Failed to create tests directory at: $playwrightTestsPath"
            }
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
                if (!(New-DirectoryIfNotExists -Path $destinationDir -Description "destination directory")) {
                    Write-Warning "Failed to create destination directory: $destinationDir. Skipping file: $($file.Name)"
                    continue
                }
            }
            
            # Copy the file
            try {
                Copy-Item -Path $file.FullName -Destination $destinationPath -Force
                Write-Host "Copied: $($file.Name) -> $relativePath"
            } catch {
                Write-Warning "Failed to copy $($file.Name): $($_.Exception.Message)"
            }
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
        [string]$Trace = "off",
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
        
        # Build the test command with performance optimizations
        $testCommand = "npx playwright test"
        
        # Add browser specification if provided
        if (![string]::IsNullOrWhiteSpace($Browser)) {
            $testCommand += " --project=$Browser"
            Write-Host "Running tests on browser: $Browser"
        }
        
        # Force headless mode for CI/CD performance
        #$testCommand += " --headed=false"
        #Write-Host "Running in headless mode for optimal CI/CD performance"
        
        # Add trace configuration if provided
        if (![string]::IsNullOrWhiteSpace($Trace) -and $Trace -ne "off") {
            $testCommand += " --trace=$Trace"
            Write-Host "Trace mode enabled: $Trace"
            
            # Inform user about trace output location
            if ($Trace -ne "off") {
                Write-Host "Trace files will be saved to: test-results folder"
            }
        } else {
            Write-Host "Trace mode: disabled for faster execution"
        }
        
        # Add performance optimizations for CI/CD
        $testCommand += " --workers=2"  # Limit workers to prevent resource exhaustion
        #$testCommand += " --reporter=junit,html,line"  # Testing handled in playwright config
        
        # Add test pattern if specified
        if (![string]::IsNullOrWhiteSpace($TestPattern)) {
            $testCommand += " $TestPattern"
        }
        
        # Add additional flags for better debugging and performance
        $testCommand += " --output=test-results" 
        $testCommand += " --max-failures=10"  # Stop after 10 failures to save time
        
        Write-Host "Executing command: $testCommand"
        Write-Host "Starting Playwright test execution with performance optimizations..."
        
        # Execute the tests
        Invoke-Expression $testCommand
        
        $testExitCode = $LASTEXITCODE
        
        if ($testExitCode -eq 0) {
            Write-Host "All Playwright tests passed successfully!" -ForegroundColor Green
        } else {
            Write-Warning "Some Playwright tests failed or encountered issues (Exit Code: $testExitCode)"
            
            # Provide detailed failure analysis
            Write-Host "============================================" -ForegroundColor Red
            Write-Host "DETAILED TEST FAILURE ANALYSIS" -ForegroundColor Red
            Write-Host "============================================" -ForegroundColor Red
            
            # Check if test results exist and analyze them
            $resultsPath = Join-Path $playwrightPath "test-results"
            if (Test-Path $resultsPath) {
                Write-Host "Test results available at: $resultsPath"
                
                # Look for JSON results files for detailed error information
                $jsonResults = Get-ChildItem -Path $resultsPath -Recurse -Filter "*.json" -ErrorAction SilentlyContinue
                if ($jsonResults) {
                    Write-Host "Found JSON result files:" -ForegroundColor Yellow
                    foreach ($jsonFile in $jsonResults | Select-Object -First 5) {
                        Write-Host "  - $($jsonFile.FullName)" -ForegroundColor Yellow
                        try {
                            $content = Get-Content $jsonFile.FullName -Raw | ConvertFrom-Json
                            if ($content.errors) {
                                Write-Host "    Errors found in $($jsonFile.Name):" -ForegroundColor Red
                                $content.errors | ForEach-Object { Write-Host "      - $_" -ForegroundColor Red }
                            }
                        } catch {
                            Write-Host "    Could not parse JSON file: $($jsonFile.Name)"
                        }
                    }
                }
                
                # Look for trace files
                $traceFiles = Get-ChildItem -Path $resultsPath -Recurse -Filter "trace.zip" -ErrorAction SilentlyContinue
                if ($traceFiles) {
                    Write-Host "Trace files found (for detailed debugging):" -ForegroundColor Cyan
                    $traceFiles | ForEach-Object { Write-Host "  - $($_.FullName)" -ForegroundColor Cyan }
                    Write-Host "Use 'npx playwright show-trace <trace-file>' to view detailed trace" -ForegroundColor Cyan
                }
                
                # Look for screenshots
                $screenshots = Get-ChildItem -Path $resultsPath -Recurse -Filter "*.png" -ErrorAction SilentlyContinue
                if ($screenshots) {
                    Write-Host "Screenshot evidence found:" -ForegroundColor Magenta
                    $screenshots | Select-Object -First 10 | ForEach-Object { Write-Host "  - $($_.FullName)" -ForegroundColor Magenta }
                }
                
                # Look for videos
                $videos = Get-ChildItem -Path $resultsPath -Recurse -Filter "*.webm" -ErrorAction SilentlyContinue
                if ($videos) {
                    Write-Host "Video recordings found:" -ForegroundColor Blue
                    $videos | Select-Object -First 5 | ForEach-Object { Write-Host "  - $($_.FullName)" -ForegroundColor Blue }
                }
            } else {
                Write-Host "No test-results directory found" -ForegroundColor Red
            }
            
            # Check if HTML report exists
            $reportPath = Join-Path $playwrightPath "playwright-report"
            if (Test-Path $reportPath) {
                Write-Host "HTML report available at: $reportPath" -ForegroundColor Green
                $indexPath = Join-Path $reportPath "index.html"
                if (Test-Path $indexPath) {
                    Write-Host "Open the following file in a browser for detailed test report:" -ForegroundColor Green
                    Write-Host "  file:///$($indexPath.Replace('\', '/'))" -ForegroundColor Green
                }
            } else {
                Write-Host "No HTML report directory found" -ForegroundColor Red
            }
            
            # Try to extract recent console output or error logs
            $logFiles = Get-ChildItem -Path $playwrightPath -Recurse -Filter "*.log" -ErrorAction SilentlyContinue
            if ($logFiles) {
                Write-Host "Log files found:" -ForegroundColor Yellow
                $logFiles | Select-Object -First 3 | ForEach-Object {
                    Write-Host "  - $($_.FullName)" -ForegroundColor Yellow
                    try {
                        $logContent = Get-Content $_.FullName -Tail 20 -ErrorAction SilentlyContinue
                        if ($logContent) {
                            Write-Host "    Last 20 lines of $($_.Name):" -ForegroundColor Gray
                            $logContent | ForEach-Object { Write-Host "      $_" -ForegroundColor Gray }
                        }
                    } catch {
                        Write-Host "    Could not read log file: $($_.Name)"
                    }
                }
            }
            
            # Provide troubleshooting suggestions
            Write-Host "============================================" -ForegroundColor Yellow
            Write-Host "TROUBLESHOOTING SUGGESTIONS:" -ForegroundColor Yellow
            Write-Host "============================================" -ForegroundColor Yellow
            Write-Host "1. Check the HTML report for detailed test execution flow" -ForegroundColor Yellow
            Write-Host "2. Review screenshots to see the state when tests failed" -ForegroundColor Yellow
            Write-Host "3. Use trace files for step-by-step debugging" -ForegroundColor Yellow
            Write-Host "4. Verify environment variables are correctly set:" -ForegroundColor Yellow
            Write-Host "   - APP_URL: $($env:APP_URL)" -ForegroundColor Yellow
            Write-Host "   - APP_NAME: $($env:APP_NAME)" -ForegroundColor Yellow
            Write-Host "   - O365_USERNAME: $(if($env:O365_USERNAME) { '[SET]' } else { '[NOT SET]' })" -ForegroundColor Yellow
            Write-Host "   - O365_PASSWORD: $(if($env:O365_PASSWORD) { '[SET]' } else { '[NOT SET]' })" -ForegroundColor Yellow
            Write-Host "5. Ensure the target application is accessible and responsive" -ForegroundColor Yellow
            Write-Host "============================================" -ForegroundColor Yellow
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

# Copy test results and reports to output location
function Copy-TestResultsToOutput {
    param(
        [string]$PlaywrightFolder = "playwright",
        [string]$OutputLocation
    )
    
    Write-Host "Copying test results and reports to output location..."
    
    # Get the playwright folder path
    $currentDir = Get-Location
    $playwrightPath = Join-Path $currentDir $PlaywrightFolder
    
    try {
        # Validate output location
        if ([string]::IsNullOrWhiteSpace($OutputLocation)) {
            Write-Warning "No output location specified. Skipping results copy operation."
            return
        }
        
        # Check if playwright folder exists
        if (!(Test-Path $playwrightPath)) {
            Write-Warning "Playwright folder not found at: $playwrightPath. No results to copy."
            return
        }
        
        # Create output location if it doesn't exist
        if (!(Test-Path $OutputLocation)) {
            if (!(New-DirectoryIfNotExists -Path $OutputLocation -Description "output directory")) {
                throw "Failed to create output directory: $OutputLocation"
            }
        }
        
        # Define source and destination paths
        $sourceTestResults = Join-Path $playwrightPath "test-results"
        $sourceReports = Join-Path $playwrightPath "playwright-report"
        $destTestResults = Join-Path $OutputLocation "test-results"
        $destReports = Join-Path $OutputLocation "playwright-report"
        
        # Copy test-results folder if it exists
        if (Test-Path $sourceTestResults) {
            Write-Host "Copying test-results from: $sourceTestResults"
            Write-Host "Copying test-results to: $destTestResults"
            
            try {
                # Remove existing destination if it exists
                if (Test-Path $destTestResults) {
                    Write-Host "Removing existing test-results folder..."
                    Remove-Item -Path $destTestResults -Recurse -Force
                }
                
                # Ensure parent directory exists and create the full path
                $destParent = Split-Path $destTestResults -Parent
                if (!(Test-Path $destParent)) {
                    Write-Host "Creating parent directory: $destParent"
                    New-Item -Path $destParent -ItemType Directory -Force | Out-Null
                }
                
                # Copy the entire folder structure
                Write-Host "Copying test-results folder structure..."
                Copy-Item -Path $sourceTestResults -Destination $OutputLocation -Recurse -Force
                Write-Host "Successfully copied test-results folder"
            } catch {
                Write-Warning "Failed to copy test-results folder: $($_.Exception.Message)"
                Write-Host "Attempting alternative copy method..."
                try {
                    # Alternative method: Create destination first, then copy contents
                    if (!(Test-Path $destTestResults)) {
                        New-Item -Path $destTestResults -ItemType Directory -Force | Out-Null
                    }
                    Copy-Item -Path "$sourceTestResults\*" -Destination $destTestResults -Recurse -Force
                    Write-Host "Successfully copied test-results using alternative method"
                } catch {
                    Write-Error "Failed to copy test-results with both methods: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Warning "No test-results folder found at: $sourceTestResults"
        }
        
        # Copy playwright-report folder if it exists
        if (Test-Path $sourceReports) {
            Write-Host "Copying playwright-report from: $sourceReports"
            Write-Host "Copying playwright-report to: $destReports"
            
            try {
                # Remove existing destination if it exists
                if (Test-Path $destReports) {
                    Write-Host "Removing existing playwright-report folder..."
                    Remove-Item -Path $destReports -Recurse -Force
                }
                
                # Ensure parent directory exists and create the full path
                $destParent = Split-Path $destReports -Parent
                if (!(Test-Path $destParent)) {
                    Write-Host "Creating parent directory: $destParent"
                    New-Item -Path $destParent -ItemType Directory -Force | Out-Null
                }
                
                # Copy the entire folder structure
                Write-Host "Copying playwright-report folder structure..."
                Copy-Item -Path $sourceReports -Destination $OutputLocation -Recurse -Force
                Write-Host "Successfully copied playwright-report folder"
            } catch {
                Write-Warning "Failed to copy playwright-report folder: $($_.Exception.Message)"
                Write-Host "Attempting alternative copy method..."
                try {
                    # Alternative method: Create destination first, then copy contents
                    if (!(Test-Path $destReports)) {
                        New-Item -Path $destReports -ItemType Directory -Force | Out-Null
                    }
                    Copy-Item -Path "$sourceReports\*" -Destination $destReports -Recurse -Force
                    Write-Host "Successfully copied playwright-report using alternative method"
                } catch {
                    Write-Error "Failed to copy playwright-report with both methods: $($_.Exception.Message)"
                }
            }
        } else {
            Write-Warning "No playwright-report folder found at: $sourceReports"
        }
        
        # Summary
        Write-Host "Test results and reports copy operation completed"
        Write-Host "Output location: $OutputLocation"
        
        
    } catch {
        Write-Error "Failed to copy test results and reports: $($_.Exception.Message)"
        throw
    }
}

# Display the developer message
$developerMessage = Fetch-DeveloperMessage
Write-Host "Developer Message: $developerMessage"

# Get inputs from the task
$testLocation = Get-VstsInput -Name 'testLocation'
$browser = Get-VstsInput -Name 'browser'
$trace = Get-VstsInput -Name 'trace'
$outputLocation = Get-VstsInput -Name 'outputLocation'
$appUrl = Get-VstsInput -Name 'appUrl'
$appName = Get-VstsInput -Name 'appName'
$o365Username = Get-VstsInput -Name 'o365Username'
$o365Password = Get-VstsInput -Name 'o365Password'
$playwrightRepository = Get-VstsInput -Name 'playwrightRepository'
$playwrightBranch = Get-VstsInput -Name 'playwrightBranch'
$branchName = Get-VstsInput -Name 'branchName'
$tags = Get-VstsInput -Name 'tags'

# Set environment variables for Playwright tests and performance optimizations
Write-Host "==========================================================="
Write-Host "Setting environment variables for Playwright tests..."

# Performance optimizations for CI/CD
$env:PLAYWRIGHT_BROWSERS_PATH = "0"  # Use system temp for browser binaries
$env:PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "0"  # Ensure we can download browsers
$env:CI = "true"  # Enable CI mode optimizations in Playwright

if (![string]::IsNullOrWhiteSpace($appUrl)) {
    $env:APP_URL = $appUrl
    Write-Host "APP_URL environment variable set"
} else {
    Write-Host "APP_URL not provided - skipping"
}

if (![string]::IsNullOrWhiteSpace($appName)) {
    $env:APP_NAME = $appName
    Write-Host "APP_NAME environment variable set"
} else {
    Write-Host "APP_NAME not provided - skipping"
}

if (![string]::IsNullOrWhiteSpace($o365Username)) {
    $env:O365_USERNAME = $o365Username
    Write-Host "O365_USERNAME environment variable set"
} else {
    Write-Host "O365_USERNAME not provided - skipping"
}

if (![string]::IsNullOrWhiteSpace($o365Password)) {
    $env:O365_PASSWORD = $o365Password
    Write-Host "O365_PASSWORD environment variable set"
} else {
    Write-Host "O365_PASSWORD not provided - skipping"
}

# Set browser preference early for optimization
if (![string]::IsNullOrWhiteSpace($browser)) {
    $env:PLAYWRIGHT_BROWSER = $browser
    Write-Host "Target browser set to: $browser for optimized installation"
}

Write-Host "Performance optimizations enabled for CI/CD environment"
Write-Host "==========================================================="

# Install Node.js on the target machine
Write-Host "==========================================================="
Write-Host "Installing Node.js..."
Install-NodeJS
Write-Host "==========================================================="

# Clone Playwright repository
Write-Host "==========================================================="
Write-Host "Cloning Playwright repository..."

# Use custom repository URL if provided, otherwise use default
$repositoryUrl = if (![string]::IsNullOrWhiteSpace($playwrightRepository)) { $playwrightRepository } else { "https://github.com/itweedie/playwrightOnPowerPlatform.git" }

# Call function with branch parameter
Clone-PlaywrightRepository -RepositoryUrl $repositoryUrl -Branch $playwrightBranch

Write-Host "==========================================================="

# Install Playwright from the cloned repository
Write-Host "==========================================================="
Write-Host "Installing Playwright from repository..."
Install-PlaywrightFromRepository -TargetBrowser $browser
Write-Host "==========================================================="

# Copy tests from specified location to playwright tests folder
Write-Host "==========================================================="
Write-Host "Copying tests to Playwright tests folder..."
Copy-TestsToPlaywright -TestLocation $testLocation
Write-Host "==========================================================="

# Run Playwright tests
Write-Host "==========================================================="
Write-Host "Running Playwright tests..."
$testResults = Run-PlaywrightTests -Browser $browser -Trace $trace
Write-Host "==========================================================="

# Copy test results and reports to output location
Write-Host "==========================================================="
Write-Host "Copying test results and reports to output location..."
Copy-TestResultsToOutput -OutputLocation $outputLocation
Write-Host "==========================================================="


# Output the script information at runtime
Write-Host "==========================================================="
Write-Host "Task: Mightora Playwright for Power Platform"
Write-Host "Originally Created By: Ian Tweedie [https://iantweedie.biz] (Date: 2025-05-25)"
Write-Host "Contributors:"
#Write-Host " - Developer A (Contributions: Improved Git configuration handling)"
#Write-Host " - Developer B (Contributions: Added support for custom commit messages)"
Write-Host "==========================================================="
