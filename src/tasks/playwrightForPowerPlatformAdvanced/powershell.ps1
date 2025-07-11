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

# Helper function to mask sensitive values in logs
function Write-SecureHost {
    param(
        [string]$Message,
        [string]$SensitiveValue = $null,
        [string]$MaskValue = "[SECURE VALUE SET]"
    )
    
    if (![string]::IsNullOrWhiteSpace($SensitiveValue)) {
        Write-Host "$Message $MaskValue"
    } else {
        Write-Host "$Message [NOT SET]"
    }
}

# Helper function to test Power Platform API access
function Test-PowerPlatformAccess {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken
    )
    
    Write-Host "Testing Power Platform API access..."
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Test API access with a simple query
        $testQuery = "$formattedDynamicsUrl/api/data/v9.2/WhoAmI"
        Write-Host "Testing API access: $testQuery"
        
        $response = Invoke-RestMethod -Uri $testQuery -Method GET -Headers $headers -ErrorAction Stop
        
        if ($response.UserId) {
            Write-Host "API access test successful. Service principal user ID: $($response.UserId)" -ForegroundColor Green
            return $true
        } else {
            Write-Warning "API access test completed but no user ID returned"
            return $false
        }
        
    } catch {
        Write-Error "Power Platform API access test failed: $($_.Exception.Message)"
        
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            $statusDescription = $_.Exception.Response.StatusDescription
            Write-Error "HTTP Status: $statusCode - $statusDescription"
            
            if ($statusCode -eq 401) {
                Write-Error "CRITICAL: The service principal does not have access to Power Platform."
                Write-Error "Required steps to fix this issue:"
                Write-Error "1. Register the app in Azure AD if not already done"
                Write-Error "2. Add 'Dynamics CRM' API permissions to the app registration"
                Write-Error "3. Grant admin consent for the API permissions"
                Write-Error "4. Add the service principal as an application user in Power Platform admin center"
                Write-Error "5. Assign appropriate security roles to the application user"
                Write-Error ""
                Write-Error "Power Platform Admin Center > Environments > [Your Environment] > Settings > Users + permissions > Application users"
            }
        }
        
        return $false
    }
}

# Get Access Token from Azure AD using Client Credentials
function Get-PowerPlatformAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret,
        [string]$DynamicsUrl
    )
    
    Write-Host "==========================================================="
    Write-Host "Authenticating with Azure AD to get Power Platform access token..."
    
    try {
        # Validate required parameters
        if ([string]::IsNullOrWhiteSpace($TenantId)) {
            throw "Tenant ID is required for authentication"
        }
        if ([string]::IsNullOrWhiteSpace($ClientId)) {
            throw "Client ID is required for authentication"
        }
        if ([string]::IsNullOrWhiteSpace($ClientSecret)) {
            throw "Client Secret is required for authentication"
        }
        if ([string]::IsNullOrWhiteSpace($DynamicsUrl)) {
            throw "Dynamics URL is required for authentication"
        }
        
        # Log authentication attempt (securely)
        Write-Host "Tenant ID: $TenantId"
        Write-Host "Client ID: $ClientId"
        Write-SecureHost -Message "Client Secret:" -SensitiveValue $ClientSecret
        Write-Host "Dynamics URL: $DynamicsUrl"
        
        # Prepare token request
        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        
        # Ensure the Dynamics URL is properly formatted for the scope
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        # Remove trailing slash if present
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        $scope = "$formattedDynamicsUrl/.default"
        
        $body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            scope         = $scope
        }
        
        Write-Host "Requesting access token from Azure AD..."
        Write-Host "Token URL: $tokenUrl"
        Write-Host "Formatted Dynamics URL: $formattedDynamicsUrl"
        Write-Host "Scope: $scope"
        
        # Make the token request
        $response = Invoke-RestMethod -Uri $tokenUrl -Method POST -Body $body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        
        if ($response.access_token) {
            Write-Host "Successfully obtained access token" -ForegroundColor Green
            Write-Host "Token type: $($response.token_type)"
            Write-Host "Token expires in: $($response.expires_in) seconds"
            return $response.access_token
        } else {
            throw "No access token received in response"
        }
        
    } catch {
        Write-Error "Failed to obtain access token: $($_.Exception.Message)"
        
        # Enhanced error reporting for OAuth issues
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            $statusDescription = $_.Exception.Response.StatusDescription
            Write-Error "HTTP Status: $statusCode - $statusDescription"
            
            try {
                $errorResponse = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $errorBody = $reader.ReadToEnd()
                Write-Error "Error response body: $errorBody"
                
                # Try to parse the error for common OAuth issues
                if ($errorBody -like "*invalid_scope*") {
                    Write-Error "TROUBLESHOOTING: Invalid scope error detected. Please verify:"
                    Write-Error "1. The Dynamics URL is correct and accessible"
                    Write-Error "2. The service principal has been granted permissions to Dynamics 365"
                    Write-Error "3. Admin consent has been provided for the required permissions"
                }
                elseif ($errorBody -like "*invalid_client*") {
                    Write-Error "TROUBLESHOOTING: Invalid client error detected. Please verify:"
                    Write-Error "1. The Client ID is correct"
                    Write-Error "2. The Client Secret is valid and not expired"
                    Write-Error "3. The service principal exists in the tenant"
                }
                elseif ($errorBody -like "*invalid_request*") {
                    Write-Error "TROUBLESHOOTING: Invalid request error detected. Please verify:"
                    Write-Error "1. All required parameters are provided"
                    Write-Error "2. The Tenant ID is correct"
                    Write-Error "3. The request format matches OAuth 2.0 client credentials flow"
                }
                
            } catch {
                Write-Warning "Could not read error response details: $($_.Exception.Message)"
            }
        }
        
        # Additional troubleshooting information
        Write-Error "CONFIGURATION VERIFICATION:"
        Write-Error "- Tenant ID: $TenantId"
        Write-Error "- Client ID: $ClientId"
        Write-Error "- Dynamics URL: $formattedDynamicsUrl"
        Write-Error "- Token URL: $tokenUrl"
        Write-Error "- Scope: $scope"
        
        throw
    }
}

# Get user ID by username from Power Platform
function Get-PowerPlatformUserId {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$Username
    )
    
    Write-Host "Getting user ID for username: $Username"
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Query for user by domainname (username)
        $userQuery = "$formattedDynamicsUrl/api/data/v9.2/systemusers?`$filter=domainname eq '$Username'"
        Write-Host "Querying user: $userQuery"
        
        $response = Invoke-RestMethod -Uri $userQuery -Method GET -Headers $headers -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            $userId = $response.value[0].systemuserid
            $fullName = $response.value[0].fullname
            Write-Host "Found user: $fullName (ID: $userId)" -ForegroundColor Green
            return $userId
        } else {
            throw "User not found: $Username"
        }
        
    } catch {
        Write-Error "Failed to get user ID: $($_.Exception.Message)"
        
        # Enhanced error reporting for API access issues
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            $statusDescription = $_.Exception.Response.StatusDescription
            Write-Error "HTTP Status: $statusCode - $statusDescription"
            
            if ($statusCode -eq 401) {
                Write-Error "TROUBLESHOOTING: Authentication/Authorization failed. Please verify:"
                Write-Error "1. The service principal has 'Dynamics 365' API permissions"
                Write-Error "2. The service principal is added as an application user in Power Platform"
                Write-Error "3. The application user has appropriate security roles assigned"
                Write-Error "4. The access token is valid and not expired"
                Write-Error "5. The Dynamics URL is correct: $formattedDynamicsUrl"
            }
            
            try {
                $errorResponse = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorResponse)
                $errorBody = $reader.ReadToEnd()
                Write-Error "Error response body: $errorBody"
            } catch {
                Write-Warning "Could not read error response details: $($_.Exception.Message)"
            }
        }
        
        throw
    }
}

# Get role ID by role name
function Get-PowerPlatformRoleId {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$RoleName
    )
    
    Write-Host "Getting role ID for role: $RoleName"
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Query for role by name
        $roleQuery = "$formattedDynamicsUrl/api/data/v9.2/roles?`$filter=name eq '$RoleName'"
        Write-Host "Querying role: $roleQuery"
        
        $response = Invoke-RestMethod -Uri $roleQuery -Method GET -Headers $headers -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            $roleId = $response.value[0].roleid
            Write-Host "Found role: $RoleName (ID: $roleId)" -ForegroundColor Green
            return $roleId
        } else {
            throw "Role not found: $RoleName"
        }
        
    } catch {
        Write-Error "Failed to get role ID: $($_.Exception.Message)"
        
        # Enhanced error reporting for API access issues
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 401) {
                Write-Error "TROUBLESHOOTING: Authentication failed when accessing roles. The service principal may not have sufficient permissions."
            }
        }
        
        throw
    }
}

# Get team ID by team name
function Get-PowerPlatformTeamId {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$TeamName
    )
    
    Write-Host "Getting team ID for team: $TeamName"
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Query for team by name
        $teamQuery = "$formattedDynamicsUrl/api/data/v9.2/teams?`$filter=name eq '$TeamName'"
        Write-Host "Querying team: $teamQuery"
        
        $response = Invoke-RestMethod -Uri $teamQuery -Method GET -Headers $headers -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            $teamId = $response.value[0].teamid
            Write-Host "Found team: $TeamName (ID: $teamId)" -ForegroundColor Green
            return $teamId
        } else {
            throw "Team not found: $TeamName"
        }
        
    } catch {
        Write-Error "Failed to get team ID: $($_.Exception.Message)"
        
        # Enhanced error reporting for API access issues
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 401) {
                Write-Error "TROUBLESHOOTING: Authentication failed when accessing teams. The service principal may not have sufficient permissions."
            }
        }
        
        throw
    }
}

# Get business unit ID by business unit name
function Get-PowerPlatformBusinessUnitId {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$BusinessUnitName
    )
    
    Write-Host "Getting business unit ID for: $BusinessUnitName"
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Query for business unit by name
        $buQuery = "$formattedDynamicsUrl/api/data/v9.2/businessunits?`$filter=name eq '$BusinessUnitName'"
        Write-Host "Querying business unit: $buQuery"
        
        $response = Invoke-RestMethod -Uri $buQuery -Method GET -Headers $headers -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            $businessUnitId = $response.value[0].businessunitid
            Write-Host "Found business unit: $BusinessUnitName (ID: $businessUnitId)" -ForegroundColor Green
            return $businessUnitId
        } else {
            throw "Business unit not found: $BusinessUnitName"
        }
        
    } catch {
        Write-Error "Failed to get business unit ID: $($_.Exception.Message)"
        
        # Enhanced error reporting for API access issues
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 401) {
                Write-Error "TROUBLESHOOTING: Authentication failed when accessing business units. The service principal may not have sufficient permissions."
            }
        }
        
        throw
    }
}

# Remove all security roles from user
function Remove-AllUserSecurityRoles {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId
    )
    
    Write-Host "==========================================================="
    Write-Host "Removing all existing security roles from user..."
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Get current user roles
        $userRolesQuery = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association"
        Write-Host "Querying current user roles..."
        
        $response = Invoke-RestMethod -Uri $userRolesQuery -Method GET -Headers $headers -ErrorAction Stop
        
        if ($response.value -and $response.value.Count -gt 0) {
            Write-Host "Found $($response.value.Count) existing roles to remove"
            
            foreach ($role in $response.value) {
                $roleId = $role.roleid
                $roleName = $role.name
                
                try {
                    # Remove role association
                    $removeUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association/$roleId/`$ref"
                    Invoke-RestMethod -Uri $removeUrl -Method DELETE -Headers $headers -ErrorAction Stop
                    Write-Host "Removed role: $roleName" -ForegroundColor Yellow
                } catch {
                    Write-Warning "Failed to remove role $roleName`: $($_.Exception.Message)"
                }
            }
            
            Write-Host "Completed removal of existing security roles" -ForegroundColor Green
        } else {
            Write-Host "No existing security roles found for user" -ForegroundColor Green
        }
        
    } catch {
        Write-Error "Failed to remove user security roles: $($_.Exception.Message)"
        
        # Enhanced error reporting for API access issues
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode
            if ($statusCode -eq 401) {
                Write-Error "TROUBLESHOOTING: Authentication failed when accessing user roles. The service principal may not have sufficient permissions to modify user security roles."
            }
        }
        
        throw
    }
}

# Assign security role to user
function Add-UserSecurityRole {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId,
        [string]$RoleId
    )
    
    Write-Host "Assigning security role to user..."
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Associate role with user
        $associateUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association/`$ref"
        $body = @{
            "@odata.id" = "$formattedDynamicsUrl/api/data/v9.2/roles($RoleId)"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $associateUrl -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully assigned security role to user" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to assign security role: $($_.Exception.Message)"
        throw
    }
}

# Update user business unit
function Update-UserBusinessUnit {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId,
        [string]$BusinessUnitId
    )
    
    Write-Host "Updating user business unit..."
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Update user's business unit
        $updateUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)"
        $body = @{
            "businessunitid@odata.bind" = "/businessunits($BusinessUnitId)"
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $updateUrl -Method PATCH -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully updated user business unit" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to update business unit: $($_.Exception.Message)"
        throw
    }
}

# Add user to team
function Add-UserToTeam {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId,
        [string]$TeamId
    )
    
    Write-Host "Adding user to team..."
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Content-Type" = "application/json"
        }
        
        # Add user to team using the Dataverse Action API for reliability
        $addToTeamUrl = "$formattedDynamicsUrl/api/data/v9.2/AddUserToTeam"
        $body = @{
            "TeamId" = $TeamId
            "SystemUserId" = $UserId
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $addToTeamUrl -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully added user to team" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to add user to team: $($_.Exception.Message)"
        throw
    }
}

# Remove user from team
function Remove-UserFromTeam {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId,
        [string]$TeamId
    )
    
    Write-Host "Removing user from team..."
    
    try {
        # Ensure the Dynamics URL is properly formatted
        $formattedDynamicsUrl = $DynamicsUrl
        if ($formattedDynamicsUrl -notmatch "^https://") {
            $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
        }
        $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
        
        $headers = @{
            "Authorization" = "Bearer $AccessToken"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
        }
        
        # Remove user from team using the correct Dataverse API format
        $removeUrl = "$formattedDynamicsUrl/api/data/v9.2/RemoveUserFromTeam"
        $body = @{
            "TeamId" = $TeamId
            "SystemUserId" = $UserId
        } | ConvertTo-Json
        
        $headers["Content-Type"] = "application/json"
        Invoke-RestMethod -Uri $removeUrl -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully removed user from team" -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to remove user from team: $($_.Exception.Message)"
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
        & npm ci --prefer-offline --no-audit --no-fund
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "npm ci failed, falling back to npm install..."
            & npm install --prefer-offline --no-audit --no-fund
            if ($LASTEXITCODE -ne 0) {
                throw "npm install failed with exit code: $LASTEXITCODE"
            }
        }
        
        Write-Host "npm dependencies installed successfully"
        
        # Install Playwright browsers - optimized for specific browser only
        Write-Host "Installing Playwright browsers (optimized for target browser only)..."
        
        # Get browser from environment or default to chromium
        $targetBrowser = if ($env:PLAYWRIGHT_BROWSER) { $env:PLAYWRIGHT_BROWSER } else { "chromium" }
        
        Write-Host "Installing only $targetBrowser browser for faster execution..."
        & npx playwright install $targetBrowser
        
        if ($LASTEXITCODE -ne 0) {
            throw "Playwright browser installation failed with exit code: $LASTEXITCODE"
        }
        
        Write-Host "Playwright browsers installed successfully"
        
        # Install only system dependencies for the specific browser (much faster)
        Write-Host "Installing Playwright system dependencies for $targetBrowser..."
        & npx playwright install-deps $targetBrowser
        
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
        #$testCommand += " --reporter=line"  # Use faster line reporter
        
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

# Get new Power Platform advanced inputs
$tenantId = Get-VstsInput -Name 'tenantId'
$dynamicsUrl = Get-VstsInput -Name 'dynamicsUrl'
$clientId = Get-VstsInput -Name 'clientId'
$clientSecret = Get-VstsInput -Name 'clientSecret'
$userRole = Get-VstsInput -Name 'userRole'
$team = Get-VstsInput -Name 'team'
$businessUnit = Get-VstsInput -Name 'businessUnit'

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

# Set advanced Power Platform environment variables
if (![string]::IsNullOrWhiteSpace($tenantId)) {
    $env:TENANT_ID = $tenantId
    Write-Host "TENANT_ID environment variable set"
} else {
    Write-Host "TENANT_ID not provided - skipping advanced configuration"
}

if (![string]::IsNullOrWhiteSpace($dynamicsUrl)) {
    $env:DYNAMICS_URL = $dynamicsUrl
    Write-Host "DYNAMICS_URL environment variable set"
} else {
    Write-Host "DYNAMICS_URL not provided - skipping advanced configuration"
}

if (![string]::IsNullOrWhiteSpace($clientId)) {
    $env:CLIENT_ID = $clientId
    Write-Host "CLIENT_ID environment variable set"
} else {
    Write-Host "CLIENT_ID not provided - skipping advanced configuration"
}

if (![string]::IsNullOrWhiteSpace($clientSecret)) {
    $env:CLIENT_SECRET = $clientSecret
    Write-SecureHost -Message "CLIENT_SECRET environment variable" -SensitiveValue $clientSecret
} else {
    Write-Host "CLIENT_SECRET not provided - skipping advanced configuration"
}

if (![string]::IsNullOrWhiteSpace($userRole)) {
    $env:USER_ROLE = $userRole
    Write-Host "USER_ROLE environment variable set: $userRole"
} else {
    Write-Host "USER_ROLE not provided - skipping role assignment"
}

if (![string]::IsNullOrWhiteSpace($team)) {
    $env:USER_TEAM = $team
    Write-Host "USER_TEAM environment variable set: $team"
} else {
    Write-Host "USER_TEAM not provided - skipping team assignment"
}

if (![string]::IsNullOrWhiteSpace($businessUnit)) {
    $env:USER_BUSINESS_UNIT = $businessUnit
    Write-Host "USER_BUSINESS_UNIT environment variable set: $businessUnit"
} else {
    Write-Host "USER_BUSINESS_UNIT not provided - skipping business unit assignment"
}

# Set browser preference early for optimization
if (![string]::IsNullOrWhiteSpace($browser)) {
    $env:PLAYWRIGHT_BROWSER = $browser
    Write-Host "Target browser set to: $browser for optimized installation"
}

Write-Host "Performance optimizations enabled for CI/CD environment"
Write-Host "==========================================================="

# Initialize variables for cleanup
$accessToken = $null
$userId = $null
$roleId = $null
$teamId = $null
$businessUnitId = $null
$originalBusinessUnitId = $null
$powerPlatformConfigured = $false

# Power Platform Advanced Configuration (if all required parameters are provided)
if (![string]::IsNullOrWhiteSpace($tenantId) -and 
    ![string]::IsNullOrWhiteSpace($dynamicsUrl) -and 
    ![string]::IsNullOrWhiteSpace($clientId) -and 
    ![string]::IsNullOrWhiteSpace($clientSecret) -and 
    ![string]::IsNullOrWhiteSpace($o365Username)) {
    
    Write-Host "==========================================================="
    Write-Host "POWER PLATFORM ADVANCED CONFIGURATION ENABLED"
    Write-Host "==========================================================="
    
    try {
        # Step 1: Get Access Token
        $accessToken = Get-PowerPlatformAccessToken -TenantId $tenantId -ClientId $clientId -ClientSecret $clientSecret -DynamicsUrl $dynamicsUrl
        
        # Step 2: Test API Access
        $apiAccessTest = Test-PowerPlatformAccess -DynamicsUrl $dynamicsUrl -AccessToken $accessToken
        if (-not $apiAccessTest) {
            throw "Power Platform API access test failed. Please check service principal configuration."
        }
        
        # Step 3: Get User ID
        $userId = Get-PowerPlatformUserId -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -Username $o365Username
        
        # Step 4: Remove all existing security roles
        Remove-AllUserSecurityRoles -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId
        
        # Step 5: Configure user assignments if specified
        if (![string]::IsNullOrWhiteSpace($userRole)) {
            Write-Host "Configuring security role assignment..."
            $roleId = Get-PowerPlatformRoleId -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -RoleName $userRole
            Add-UserSecurityRole -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId -RoleId $roleId
        }
        
        if (![string]::IsNullOrWhiteSpace($businessUnit)) {
            Write-Host "Configuring business unit assignment..."
            $businessUnitId = Get-PowerPlatformBusinessUnitId -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -BusinessUnitName $businessUnit
            Update-UserBusinessUnit -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId -BusinessUnitId $businessUnitId
        }
        
        if (![string]::IsNullOrWhiteSpace($team)) {
            Write-Host "Configuring team assignment..."
            $teamId = Get-PowerPlatformTeamId -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -TeamName $team
            Add-UserToTeam -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId -TeamId $teamId
        }
        
        $powerPlatformConfigured = $true
        Write-Host "Power Platform user configuration completed successfully!" -ForegroundColor Green
        Write-Host "==========================================================="
        
    } catch {
        Write-Error "Power Platform configuration failed: $($_.Exception.Message)"
        Write-Host "Continuing with test execution without advanced configuration..."
        $powerPlatformConfigured = $false
    }
} else {
    Write-Host "==========================================================="
    Write-Host "Power Platform Advanced Configuration SKIPPED"
    Write-Host "Required parameters not provided. Continuing with basic test execution..."
    Write-Host "Required: tenantId, dynamicsUrl, clientId, clientSecret, o365Username"
    Write-Host "==========================================================="
}

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
Install-PlaywrightFromRepository -TargetBrowser $browser
Write-Host "==========================================================="

# Copy tests from specified location to playwright tests folder
Write-Host "==========================================================="
Write-Host "Copying tests to Playwright tests folder..."
Copy-TestsToPlaywright -TestLocation $testLocation
Write-Host "==========================================================="

# Initialize test results variable
$testResults = 0

try {
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

} catch {
    Write-Error "Test execution failed: $($_.Exception.Message)"
    $testResults = 1
} finally {
    # Power Platform Cleanup (if configuration was applied) - ALWAYS RUNS
    if ($powerPlatformConfigured -and $accessToken -and $userId) {
        Write-Host "==========================================================="
        Write-Host "POWER PLATFORM CLEANUP - REMOVING USER ASSIGNMENTS"
        Write-Host "==========================================================="
        
        try {
            # Remove security role if it was assigned
            if (![string]::IsNullOrWhiteSpace($userRole) -and $roleId) {
                Write-Host "Removing assigned security role..."
                try {
                    # Ensure the Dynamics URL is properly formatted
                    $formattedDynamicsUrl = $dynamicsUrl
                    if ($formattedDynamicsUrl -notmatch "^https://") {
                        $formattedDynamicsUrl = "https://$formattedDynamicsUrl"
                    }
                    $formattedDynamicsUrl = $formattedDynamicsUrl.TrimEnd('/')
                    
                    $headers = @{
                        "Authorization" = "Bearer $accessToken"
                        "OData-MaxVersion" = "4.0"
                        "OData-Version" = "4.0"
                        "Accept" = "application/json"
                    }
                    
                    $removeRoleUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($userId)/systemuserroles_association/$roleId/`$ref"
                    Invoke-RestMethod -Uri $removeRoleUrl -Method DELETE -Headers $headers -ErrorAction Stop
                    Write-Host "Successfully removed security role: $userRole" -ForegroundColor Green
                } catch {
                    Write-Warning "Failed to remove security role: $($_.Exception.Message)"
                }
            }
            
            # Remove from team if it was assigned
            if (![string]::IsNullOrWhiteSpace($team) -and $teamId) {
                Write-Host "Removing user from team..."
                Remove-UserFromTeam -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId -TeamId $teamId
            }
            
            # Note: Business unit changes are typically not reverted in cleanup as they may affect user's core access
            if (![string]::IsNullOrWhiteSpace($businessUnit)) {
                Write-Host "Note: Business unit assignment cleanup skipped to preserve user access"
            }
            
            Write-Host "Power Platform cleanup completed!" -ForegroundColor Green
            
        } catch {
            Write-Warning "Power Platform cleanup encountered issues: $($_.Exception.Message)"
            Write-Host "Manual cleanup may be required for user: $o365Username"
        }
        
        Write-Host "==========================================================="
    } else {
        Write-Host "No Power Platform cleanup required - advanced configuration was not applied"
    }
}


# Output the script information at runtime
Write-Host "==========================================================="
Write-Host "Task: Mightora Playwright for Power Platform Advanced"
Write-Host "Originally Created By: Ian Tweedie [https://iantweedie.biz] (Date: 2025-05-25)"
Write-Host "Enhanced with Power Platform User Management (Date: 2025-07-08)"
Write-Host "Contributors:"
Write-Host " - Enhanced user role, team, and business unit management"
Write-Host " - Added secure handling of sensitive authentication data"
Write-Host " - Implemented comprehensive cleanup procedures"
Write-Host "==========================================================="

# Exit with the test results code to properly signal success/failure to the pipeline
if ($testResults -ne 0) {
    Write-Host "Task completed with test failures (Exit Code: $testResults)" -ForegroundColor Red
    exit $testResults
} else {
    Write-Host "Task completed successfully!" -ForegroundColor Green
    exit 0
}

