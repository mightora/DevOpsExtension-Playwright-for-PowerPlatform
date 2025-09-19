[![Visual Studio Marketplace](https://img.shields.io/badge/Marketplace-View%20Extension-blue?logo=visual-studio)](https://marketplace.visualstudio.com/items?itemName=mightoraio.mightora-playwright-for-power-platform) 

# Playwright for Power Platform DevOps Extension

Automate end-to-end testing of your Power Platform applications with Playwright in Azure DevOps pipelines. This extension provides a comprehensive testing solution that sets up Playwright, executes tests against Power Apps, and generates detailed reports with failure analysis for CI/CD workflows.

## Overview

The **Playwright for Power Platform DevOps Extension** is a specialized Azure DevOps task that enables automated UI testing of Power Platform applications using the Playwright testing framework. This extension eliminates the complexity of setting up testing environments by automatically installing dependencies, configuring authentication, and executing comprehensive test suites.

Built specifically for Power Platform applications, this extension handles the unique challenges of testing Power Apps, including Office 365 authentication flows, dynamic loading patterns, and Power Platform-specific UI controls.

## Key Features

### 🚀 **Zero-Configuration Setup**
- Automatically installs Node.js, Playwright, and all required dependencies
- Pre-configured testing framework optimized for Power Platform applications
- No manual environment preparation required

### 🔧 **Flexible Repository Management** *(New in v1.0.15+)*
- **Custom Repository Support**: Specify your own Playwright framework repository
- **Branch/Tag Control**: Clone specific branches, tags, or commits for testing
- **Version Pinning**: Lock tests to specific framework versions for consistency
- **Development Workflow**: Test against feature branches before production deployment

### 🎯 **Power Platform Optimized**
- Native Office 365 authentication handling
- Pre-built selectors and waits for Power Platform controls
- Support for both Canvas Apps and Model-Driven Apps
- Integration with Power Platform URL patterns and behaviors

### 🔍 **Advanced Debugging & Analysis**
- Automatic screenshot capture on test failures
- Optional video recording of test execution
- Detailed trace files for step-by-step debugging
- Network activity monitoring and logging
- Comprehensive error analysis and reporting

### 🌐 **Multi-Browser Testing**
- Support for Chromium, Firefox, and WebKit browsers
- Option to run tests across all browsers simultaneously
- Browser-specific configuration and optimization

### 📊 **Enterprise-Grade Reporting**
- Interactive HTML reports with execution timeline
- JSON results for automation and integration
- JUnit XML format for CI/CD pipeline compatibility
- Automatic artifact collection and organization

## How It Works

1. **Environment Setup**: Automatically installs Node.js and Playwright testing framework
2. **Test Preparation**: Copies your test files and configures environment variables
3. **Test Execution**: Runs your Playwright tests with Power Platform optimizations
4. **Result Analysis**: Generates comprehensive reports with failure diagnostics

## Getting Started

### Prerequisites
- Azure DevOps pipeline with Windows or Linux agent
- Power Platform application URL
- Test user credentials with appropriate permissions
- Playwright test files (JavaScript or TypeScript)

### Basic Usage

Add the task to your Azure DevOps pipeline:

```yaml
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
```

### Advanced Usage with Custom Repository *(New in v1.0.15)*

```yaml
- task: mightoria-playwrightForPowerPlatform@1
  displayName: 'Run Tests with Custom Framework'
  inputs:
    testLocation: '$(System.DefaultWorkingDirectory)/tests'
    playwrightRepository: 'https://github.com/yourorg/custom-playwright-framework.git'
    playwrightBranch: 'feature/enhanced-selectors'
    browser: 'chromium'
    trace: 'on-first-retry'
    outputLocation: '$(Agent.TempDirectory)/test-results'
    appUrl: 'https://apps.powerapps.com/play/$(AppId)'
    appName: 'MyPowerApp'
    o365Username: '$(TestUser.Email)'
    o365Password: '$(TestUser.Password)'
```

### Configuration Parameters

| Parameter | Description | Required | Default |
|-----------|-------------|----------|---------|
| `testLocation` | Path to Playwright test files | Yes | `$(System.DefaultWorkingDirectory)/PlaywrightTests` |
| `playwrightRepository` | Custom Playwright framework repository URL | No | `https://github.com/itweedie/playwrightOnPowerPlatform.git` |
| `playwrightBranch` | Specific branch, tag, or commit to clone | No | *(default branch)* |
| `browser` | Browser to run tests (chromium, firefox, webkit, all) | Yes | `all` |
| `trace` | Trace mode (off, on, retain-on-failure, on-first-retry) | Yes | `off` |
| `outputLocation` | Directory for test results and reports | Yes | `$(System.DefaultWorkingDirectory)` |
| `appUrl` | Power Platform application URL | No | - |
| `appName` | Power Platform application name | No | - |
| `o365Username` | Office 365 username for authentication | No | - |
| `o365Password` | Office 365 password for authentication | No | - |

#### New Repository Management Parameters *(v1.0.15+)*

The `playwrightRepository` and `playwrightBranch` parameters provide flexibility for teams who:
- Maintain custom Playwright framework configurations
- Need to test against specific versions or feature branches
- Want to use their own forks of the Playwright testing framework
- Require version control over their testing infrastructure

**Examples:**
- Use feature branch: `playwrightBranch: "feature/new-selectors"`
- Pin to specific version: `playwrightBranch: "v2.1.0"`
- Test specific commit: `playwrightBranch: "abc123def456"`
- Custom repository: `playwrightRepository: "https://github.com/yourorg/custom-playwright-framework.git"`

## Example Test Scenarios

### Authentication Test
```javascript
test('Power Apps Login', async ({ page }) => {
  await page.goto(process.env.APP_URL);
  await page.fill('[name="loginfmt"]', process.env.O365_USERNAME);
  await page.click('[type="submit"]');
  await page.fill('[name="passwd"]', process.env.O365_PASSWORD);
  await page.click('[type="submit"]');
  await expect(page).toHaveTitle(new RegExp(process.env.APP_NAME));
});
```

### Canvas App Interaction
```javascript
test('Form Submission', async ({ page }) => {
  await page.goto(process.env.APP_URL);
  await page.waitForSelector('[data-automation-id="Canvas"]');
  
  // Fill form fields
  await page.click('[aria-label="Name input"]');
  await page.fill('[aria-label="Name input"]', 'Test User');
  
  // Submit form
  await page.click('[aria-label="Submit button"]');
  
  // Verify success
  await expect(page.locator('[aria-label="Success message"]')).toBeVisible();
});
```

## Troubleshooting

### Common Issues
- **Authentication failures**: Verify credentials and user permissions
- **Element not found errors**: Check for Power Platform loading delays
- **Timeout issues**: Increase timeout values for slow environments
- **"Unknown command: pm" errors**: *(Fixed in v1.0.15)* - Update to the latest version for improved npm command reliability

### Debugging Tools
- Review HTML reports for detailed execution flow
- Use trace files for step-by-step analysis
- Check screenshots for visual verification
- Monitor network logs for connectivity issues
- **New**: Enhanced error logging provides detailed command execution information

## Release Notes

### Version 1.0.15 - September 19, 2025 🎉

**Major Improvements & Bug Fixes**

#### 🔧 **Repository & Branch Management**
- **NEW**: Added `playwrightRepository` input parameter to specify custom Playwright framework repositories
- **NEW**: Added `playwrightBranch` input parameter to clone specific branches, tags, or commits
- **ENHANCED**: Full control over which version of Playwright tests and framework gets executed
- **USE CASE**: Teams can now maintain their own Playwright framework forks and test against feature branches

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
- To use custom repositories: Add `playwrightRepository` parameter to your task configuration
- To use specific branches: Add `playwrightBranch` parameter with your desired branch/tag/commit

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
