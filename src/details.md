[![Visual Studio Marketplace](https://img.shields.io/badge/Marketplace-View%20Extension-blue?logo=visual-studio)](https://marketplace.visualstudio.com/items?itemName=mightoraio.mightora-playwright-for-power-platform) 

# Playwright for Power Platform DevOps Extension

Revolutionize your Power Platform testing with automated end-to-end testing using Playwright in Azure DevOps pipelines. This extension provides a complete testing solution that automatically sets up the testing environment, executes comprehensive UI tests against your Power Apps, and generates detailed reports with advanced failure analysis.

**⚠️ Important: This extension requires Windows runners and is only compatible with Windows-based Azure DevOps pipeline agents.**

**Created by:**

[![Mightora Logo](https://raw.githubusercontent.com/TechTweedie/techtweedie.github.io/main/static/logo-01_150x150.png)](https://techtweedie.github.io) 

## Why Choose Playwright for Power Platform Testing?

Traditional Power Platform testing often requires manual effort and lacks integration with CI/CD pipelines. This extension bridges that gap by providing:

- **Zero Configuration Setup**: Automatically installs and configures the entire Playwright testing environment
- **Power Platform Optimized**: Pre-configured for Power Apps authentication and common testing scenarios  
- **Enterprise Ready**: Designed for Azure DevOps with comprehensive reporting and failure analysis
- **Multi-Browser Coverage**: Test across all major browsers to ensure consistent user experience

## How It Works

### 1. Automatic Environment Setup
The extension handles all the complexity of setting up a Playwright testing environment:
- Downloads and installs Node.js if not present
- Clones a specialized Playwright framework designed for Power Platform
- Installs all required npm dependencies and Playwright browsers
- Configures the testing environment with your specific parameters

### 2. Intelligent Test Execution  
- Copies your test files to the configured testing framework
- Sets up environment variables for Power Platform authentication
- Executes tests with your chosen browser configuration
- Captures comprehensive data during test execution

### 3. Advanced Failure Analysis
When tests fail, you get detailed insights:
- **Screenshots**: Visual evidence of exactly what was on screen when tests failed
- **Video Recordings**: Complete recordings of test execution for thorough analysis
- **Trace Files**: Step-by-step execution traces showing every action and its result
- **Network Logs**: HTTP requests and responses to identify connectivity issues
- **Error Extraction**: Specific error messages pulled from test results

### 4. Comprehensive Reporting
Multiple report formats ensure compatibility with your workflow:
- **HTML Reports**: Interactive reports perfect for sharing with stakeholders
- **JSON Results**: Machine-readable results for integration with other tools
- **JUnit XML**: Compatible with most CI/CD reporting systems
- **Screenshots & Videos**: Visual evidence automatically attached to results

## Key Features

### 🚀 **Zero-Configuration Setup**
- **Windows Agent Compatibility**: Designed specifically for Windows-based Azure DevOps agents
- Automatic Node.js installation and configuration
- Pre-built Playwright framework specifically designed for Power Platform
- Automatic browser installation (Chromium, Firefox, WebKit)
- No manual environment preparation required

### 🎯 **Power Platform Optimized**
- Native Office 365 authentication handling
- Pre-configured for Power Apps URL patterns
- Optimized selectors for Power Platform controls
- Built-in waits for Power Platform loading patterns

### 🔍 **Advanced Debugging Capabilities**
- Optional trace capture for step-by-step analysis
- Automatic screenshot capture on failures
- Video recording of test execution
- Network activity monitoring
- DOM snapshot capture

### 🌐 **Multi-Browser Testing**
- Support for Chromium, Firefox, and WebKit
- Option to run tests across all browsers simultaneously
- Browser-specific configuration options
- Consistent results across different browser engines

### 📊 **Enterprise-Grade Reporting**
- HTML reports with interactive timeline
- JSON results for automation integration
- JUnit XML for CI/CD pipeline integration
- Automatic artifact collection and organization

### 🔐 **Security & Authentication**
- Secure handling of Office 365 credentials
- Integration with Azure DevOps secret variables
- No credential storage in logs or artifacts
- Support for multi-factor authentication scenarios

## Advanced Task Capabilities

The advanced version of the Playwright for Power Platform task includes additional features for managing user roles, teams, and business units within the Power Platform environment. These capabilities enable:

- **User Role Management**: Assign and remove security roles for users dynamically during test execution.
- **Team Assignment**: Add users to specific teams to test team-based workflows and permissions.
- **Business Unit Configuration**: Update user business units to validate access and functionality across organizational structures.

These features are designed to streamline testing for enterprise-level Power Platform applications, ensuring that user-specific configurations are handled seamlessly within CI/CD pipelines.

## Setup & Configuration

### Prerequisites
- **Windows-based Azure DevOps pipeline agent** (Linux and macOS agents are not supported)
- Power Platform application URL
- Test user credentials with appropriate permissions
- Playwright test files written in JavaScript or TypeScript

### Basic Configuration
1. Ensure your Azure DevOps pipeline uses a **Windows agent** (e.g., `windows-latest`, `windows-2022`, or `vs2017-win2016`)
2. Install the extension in your Azure DevOps organization
3. Add the Playwright for Power Platform task to your pipeline
4. Configure the required parameters:
   - Test location path
   - Target browser(s)  
   - Power Platform app URL
   - Authentication credentials
5. Optionally enable trace mode for detailed debugging

### Example Pipeline YAML
```yaml
# Ensure you're using a Windows agent
pool:
  vmImage: 'windows-latest'

steps:
- task: mightoria-playwrightForPowerPlatform@1
  displayName: 'Run Power Platform Tests'
  inputs:
    testLocation: '$(System.DefaultWorkingDirectory)/tests'
    browser: 'chromium'
    trace: 'retain-on-failure'
    outputLocation: '$(Agent.TempDirectory)/test-results'
    appUrl: 'https://apps.powerapps.com/play/$(AppId)'
    appName: 'MyPowerApp'
    o365Username: '$(TestUser.Email)'
    o365Password: '$(TestUser.Password)'

- task: PublishTestResults@2
  condition: always()
  inputs:
    testResultsFormat: 'JUnit'
    testResultsFiles: '$(Agent.TempDirectory)/test-results/**/*.xml'
    testRunTitle: 'Power Platform UI Tests'

- task: PublishHtmlReport@1
  condition: always()
  inputs:
    reportDir: '$(Agent.TempDirectory)/test-results/playwright-report'
    tabName: 'Test Report'
```

## Common Test Scenarios

### Authentication Testing
```javascript
test('Office 365 Login Flow', async ({ page }) => {
  await page.goto(process.env.APP_URL);
  await page.fill('[name="loginfmt"]', process.env.O365_USERNAME);
  await page.click('[type="submit"]');
  await page.fill('[name="passwd"]', process.env.O365_PASSWORD);
  await page.click('[type="submit"]');
  await expect(page).toHaveTitle(new RegExp(process.env.APP_NAME));
});
```

### Canvas App Testing
```javascript
test('Form Submission Workflow', async ({ page }) => {
  await page.goto(process.env.APP_URL);
  // Wait for Power Apps to load
  await page.waitForSelector('[data-automation-id="Canvas"]');
  
  // Interact with Power Apps controls
  await page.click('[aria-label="Name input"]');
  await page.fill('[aria-label="Name input"]', 'Test User');
  await page.click('[aria-label="Submit button"]');
  
  // Verify success message
  await expect(page.locator('[aria-label="Success message"]')).toBeVisible();
});
```

## Troubleshooting & Support

### Common Issues
- **Authentication Failures**: Verify credentials and ensure test user has appropriate permissions
- **Element Not Found**: Check for Power Platform loading delays and add appropriate waits
- **Timeout Errors**: For slow-loading environments, consider increasing the default timeout in your Playwright configuration or tests.

## Contributing

This project is open source and contributions are welcome! If you'd like to report a bug, request a feature, or submit a code change, please visit our [GitHub repository](https://github.com/mightora/DevOpsExtension-Playwright-for-PowerPlatform) to open an issue or pull request.

## Release Notes

### Version 1.1.0 - September 24, 2025 🎉

**Major Improvements & Bug Fixes**

#### 🔧 **Repository & Version Management**
- **NEW**: Added `playwrightVersion` input parameter to specify versions, branches, tags, or commits
- **ENHANCED**: Full control over which version of Playwright framework gets executed
- **CONTROLLED**: Repository URL is fixed to ensure consistency and reliability across all users
- **USE CASE**: Teams can test against specific versions and pin to stable releases

#### 🛠️ **Command Execution Reliability**
- **FIXED**: Resolved "Unknown command: 'pm'" error that occurred with npm/npx commands in certain CI/CD environments
- **IMPROVED**: Replaced unreliable `&` call operator with robust `Start-Process` approach for npm/npx execution
- **ENHANCED**: Better error handling with detailed logging of exact commands being executed
- **RESULT**: More reliable installation and execution across different Azure DevOps agents and environments

#### 🚀 **Performance & Stability**
- **OPTIMIZED**: Faster npm dependency installation with improved error recovery
- **ENHANCED**: Better exit code handling and process management
- **IMPROVED**: More descriptive error messages for troubleshooting
- **ADDED**: Comprehensive logging for debugging installation issues

#### 📋 **Task Configuration**
- **UPDATED**: Both Basic and Advanced task versions now support repository management
- **CONSISTENT**: Unified input parameter handling across both task variants
- **BACKWARD COMPATIBLE**: Existing pipelines continue to work without modification

#### 🔍 **Developer Experience**
- **IMPROVED**: Clear documentation of which branch/commit is being cloned
- **ENHANCED**: Better error messages with troubleshooting guidance
- **ADDED**: Validation and compatibility checks for repository cloning

**Migration Notes:**
- Existing pipelines will continue to work unchanged (default repository and branch behavior)
- To use specific branches: Add `playwrightVersion` parameter with your desired branch/tag/commit
- Repository URL is now fixed for consistency - custom repositories are no longer supported

**Breaking Changes:**
- None - this release is fully backward compatible

---

### Previous Versions

#### Version 1.0.14 and Earlier
- Core Playwright testing functionality for Power Platform applications
- Office 365 authentication support
- Multi-browser testing capabilities
- Comprehensive reporting and debugging features

## Support & Documentation

- **Extension Documentation**: Detailed guides available in the Azure DevOps Marketplace
- **Community Support**: GitHub issues and discussions
- **Professional Support**: Available through [mightora.io](https://mightora.io)

## License

This project is licensed under the MIT License. See the LICENSE file for more details.

## Contact

For more information or support, please visit [https://mightora.io](https://mightora.io) or open an issue in this repository.

---

**Created by:** [Mightora.io](https://mightora.io) | **Powered by:** [Playwright](https://playwright.dev)
