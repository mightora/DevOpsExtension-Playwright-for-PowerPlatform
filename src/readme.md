[![Visual Studio Marketplace](https://img.shields.io/badge/Marketplace-View%20Extension-blue?logo=visual-studio)](https://marketplace.visualstudio.com/items?itemName=mightoraio.mightora-power-platform-devOps-extension)

# Playwright for Power Platform DevOps Extension

Automate end-to-end testing of your Power Platform applications with Playwright in Azure DevOps pipelines. This extension provides a comprehensive testing solution that sets up Playwright, executes tests against Power Apps, and generates detailed reports with failure analysis for CI/CD workflows.

**⚠️ Important: This extension requires Windows runners and is only compatible with Windows-based Azure DevOps pipeline agents.**

**Created by:**

[![Mightora Logo](https://raw.githubusercontent.com/TechTweedie/techtweedie.github.io/main/static/logo-01_150x150.png)](https://techtweedie.github.io) [![Playwright Logo](https://playwright.dev/img/playwright-logo.svg)](https://playwright.dev)

# Setup 
- Ensure you have a **Windows-based Azure DevOps pipeline agent** (this extension does not support Linux or macOS agents)
- Install the DevOps extension in your DevOps Organization using the **Get it free** button
- Navigate to your Azure DevOps pipeline
- Add the Playwright for Power Platform task to your pipeline
- Configure your test parameters and Power Platform credentials
- Run your pipeline to execute automated UI tests

# Support
Please visit [mightora.io](https://mightora.io)

# Key Features

## Playwright for Power Platform Testing

### Overview
This task enables automated end-to-end testing of Power Platform applications using Playwright. It handles the complete testing lifecycle from environment setup to detailed failure analysis, making it perfect for CI/CD pipelines that need to validate Power Apps functionality.

### Key Features
- **Windows Agent Compatibility**: Designed specifically for Windows-based Azure DevOps pipeline agents
- **Automated Environment Setup**: Automatically installs Node.js, Playwright, and all required dependencies
- **Power Platform Integration**: Native support for Power Apps authentication and testing scenarios
- **Multi-Browser Testing**: Execute tests across Chromium, Firefox, WebKit, or all browsers simultaneously  
- **Comprehensive Reporting**: Generates HTML reports, JSON results, JUnit XML, and detailed trace files
- **Advanced Failure Analysis**: Captures screenshots, videos, DOM snapshots, and network activity on test failures
- **Environment Variable Management**: Seamlessly passes Azure DevOps variables to test scripts
- **Trace Debugging**: Optional trace capture for step-by-step test execution analysis
- **Flexible Test Organization**: Supports custom test locations and output directories

### How It Works
1. **Environment Preparation**: The task clones a Playwright testing framework specifically designed for Power Platform
2. **Dependency Installation**: Automatically installs Node.js, npm packages, and Playwright browsers
3. **Test Execution**: Copies your tests to the framework and executes them with configured parameters
4. **Result Analysis**: Analyzes test results and provides detailed failure diagnostics
5. **Report Generation**: Creates comprehensive reports and copies them to your specified output location

### Configuration Options
- **Test Location**: Specify where your Playwright test files are stored
- **Browser Selection**: Choose specific browsers or run tests across all supported browsers
- **Trace Mode**: Enable detailed execution tracing for debugging failed tests
- **Output Location**: Define where test results and reports should be saved
- **Power Platform Settings**: Configure app URLs, names, and Office 365 credentials

### How to Use
1. Add the task to your Azure DevOps pipeline
2. Configure the required inputs:
   - `testLocation`: Path to your Playwright test files
   - `browser`: Browser(s) to run tests on (chromium, firefox, webkit, or all)
   - `outputLocation`: Directory for test results and reports
   - `appUrl`: URL of your Power Platform application
   - `o365Username` & `o365Password`: Authentication credentials for Power Apps
3. Optional configuration:
   - `trace`: Enable tracing for debugging (off, on, retain-on-failure, on-first-retry)
   - `appName`: Name of your Power Platform application
4. Run the pipeline to execute your tests

### Example Pipeline Usage

```yaml
- task: mightoria-playwrightForPowerPlatform@1
  inputs:
    testLocation: "$(System.DefaultWorkingDirectory)/PlaywrightTests"
    browser: "chromium"
    trace: "retain-on-failure"
    outputLocation: "$(System.DefaultWorkingDirectory)/TestResults"
    appUrl: "https://apps.powerapps.com/play/your-app-id"
    appName: "MyPowerApp"
    o365Username: "$(TestUserEmail)"
    o365Password: "$(TestUserPassword)"
```

### Test Failure Analysis
When tests fail, the extension provides:
- **Detailed Error Messages**: Specific failure reasons extracted from test results
- **Visual Evidence**: Screenshots captured at the moment of failure
- **Video Recordings**: Complete test execution videos (when enabled)
- **Trace Files**: Step-by-step execution traces for debugging
- **Network Analysis**: HTTP requests and responses during test execution
- **Environment Validation**: Verification of configuration and connectivity

### Supported Test Scenarios
- **Login and Authentication**: Automated Office 365 sign-in workflows
- **Navigation Testing**: Verify app navigation and page transitions
- **Form Interactions**: Test data entry, validation, and submission
- **Canvas App Testing**: Interact with Power Apps canvas controls
- **Model-Driven App Testing**: Test Dynamics 365 and model-driven apps
- **Integration Testing**: Validate connections to external systems
- **Performance Testing**: Monitor app loading times and responsiveness

### Best Practices
- Store sensitive credentials in Azure DevOps secret variables
- Use trace mode "retain-on-failure" for optimal debugging without performance impact
- Organize tests in logical groups using descriptive file names
- Set up test data cleanup to maintain test environment consistency
- Use the HTML report for detailed test analysis and sharing with stakeholders
