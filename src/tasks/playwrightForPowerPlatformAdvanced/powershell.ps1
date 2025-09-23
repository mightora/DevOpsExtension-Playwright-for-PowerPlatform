<#
    ===========================================================
    Task: Mightora Playwright for Power Platform Advanced
    
    Originally Created By: Ian Tweedie [https://iantweedie.biz] (Date: 2025-05-25)
    Enhanced with Power Platform User Management (Date: 2025-07-08)

    Contributors:
    - Enhanced user role, team, and business unit management
    - Added secure handling of sensitive authentication data
    - Implemented comprehensive cleanup procedures
    
    ===========================================================
#>

[CmdletBinding()]

param()

# Import the VSTS Task SDK with error handling
try {
    Import-Module $PSScriptRoot\ps_modules\VstsTaskSdk\VstsTaskSdk.psd1 -ErrorAction Stop
    Write-Host "VSTS Task SDK imported successfully"
} catch {
    Write-Error "Failed to import VSTS Task SDK: $($_.Exception.Message)"
    Write-Error "Ensure the ps_modules\VstsTaskSdk directory exists in: $PSScriptRoot"
    exit 1
}

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
            $statusDescription = $_.Exception.Response.StatusDescription
            Write-Error "HTTP Status: $statusCode - $statusDescription"
            
            if ($statusCode -eq 401) {
                Write-Error "TROUBLESHOOTING: Authentication failed when accessing business units. Please verify:"
                Write-Error "1. The service principal has read access to businessunit entity"
                Write-Error "2. The access token is valid and not expired"
                Write-Error "3. The service principal has appropriate permissions in Power Platform"
                Write-Error "4. The Dynamics URL is correct: $formattedDynamicsUrl"
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

# Validate user and role compatibility before assignment
function Test-UserRoleCompatibility {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId,
        [string]$RoleId
    )
    
    Write-Host "Validating user and role compatibility..."
    
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
        
        # Get user details including business unit
        $userQuery = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)?`$select=fullname,domainname,isdisabled,businessunitid,systemuserid&`$expand=businessunitid(`$select=name)"
        Write-Host "Querying user details: $userQuery"
        $userResponse = Invoke-RestMethod -Uri $userQuery -Method GET -Headers $headers -ErrorAction Stop
        
        # Get role details including business unit
        $roleQuery = "$formattedDynamicsUrl/api/data/v9.2/roles($RoleId)?`$select=name,businessunitid,roleid&`$expand=businessunitid(`$select=name)"
        Write-Host "Querying role details: $roleQuery"
        $roleResponse = Invoke-RestMethod -Uri $roleQuery -Method GET -Headers $headers -ErrorAction Stop
        
        # Display compatibility information
        Write-Host "=== USER AND ROLE COMPATIBILITY CHECK ===" -ForegroundColor Cyan
        Write-Host "User Details:" -ForegroundColor Yellow
        Write-Host "  - Name: $($userResponse.fullname)"
        Write-Host "  - Domain: $($userResponse.domainname)"
        Write-Host "  - Disabled: $($userResponse.isdisabled)"
        Write-Host "  - User Business Unit: $($userResponse.businessunitid.name) (ID: $($userResponse.businessunitid.businessunitid))"
        
        Write-Host "Role Details:" -ForegroundColor Yellow
        Write-Host "  - Role Name: $($roleResponse.name)"
        Write-Host "  - Role Business Unit: $($roleResponse.businessunitid.name) (ID: $($roleResponse.businessunitid.businessunitid))"
        
        # Check for potential issues
        $issues = @()
        
        if ($userResponse.isdisabled) {
            $issues += "User is disabled - role assignment may fail"
        }
        
        if ($userResponse.businessunitid.businessunitid -ne $roleResponse.businessunitid.businessunitid) {
            $issues += "Business unit mismatch: User is in '$($userResponse.businessunitid.name)' but role is in '$($roleResponse.businessunitid.name)'"
        }
        
        if ($issues.Count -gt 0) {
            Write-Warning "Potential compatibility issues detected:"
            $issues | ForEach-Object { Write-Warning "  - $_" }
            Write-Host "These issues may cause role assignment to fail." -ForegroundColor Red
            return $false
        } else {
            Write-Host "User and role are compatible for assignment." -ForegroundColor Green
            return $true
        }
        
    } catch {
        Write-Warning "Could not validate user/role compatibility: $($_.Exception.Message)"
        Write-Host "Proceeding with assignment attempt anyway..."
        return $true  # Don't block assignment if validation fails
    }
}

# Assign security role to user - FIXED VERSION
function Add-UserSecurityRole {
    param(
        [string]$DynamicsUrl,
        [string]$AccessToken,
        [string]$UserId,
        [string]$RoleId
    )
    
    Write-Host "Assigning security role to user..."
    
    # First, validate user and role compatibility
    $isCompatible = Test-UserRoleCompatibility -DynamicsUrl $DynamicsUrl -AccessToken $AccessToken -UserId $UserId -RoleId $RoleId
    if (-not $isCompatible) {
        Write-Warning "Compatibility issues detected, but continuing with assignment attempt..."
    }
    
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
        
        # Method 1: Try the systemuserroles_association endpoint (most common)
        try {
            Write-Host "Attempting role assignment using systemuserroles_association..."
            $associateUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association/`$ref"
            $body = @{
                "@odata.id" = "$formattedDynamicsUrl/api/data/v9.2/roles($RoleId)"
            } | ConvertTo-Json
            
            Write-Host "POST URL: $associateUrl"
            Write-Host "Request Body: $body"
            
            Invoke-RestMethod -Uri $associateUrl -Method POST -Headers $headers -Body $body -ErrorAction Stop
            Write-Host "Successfully assigned security role using systemuserroles_association" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Method 1 failed: $($_.Exception.Message)"
            
            # Check if it's a duplicate role error (which might be acceptable)
            if ($_.Exception.Message -like "*duplicate*" -or $_.Exception.Message -like "*already exists*") {
                Write-Host "Role may already be assigned. Checking current assignments..." -ForegroundColor Yellow
                
                # Verify the role is actually assigned
                $checkUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association"
                $currentRoles = Invoke-RestMethod -Uri $checkUrl -Method GET -Headers $headers -ErrorAction SilentlyContinue
                
                $roleAlreadyAssigned = $currentRoles.value | Where-Object { $_.roleid -eq $RoleId }
                if ($roleAlreadyAssigned) {
                    Write-Host "Role is already assigned to user - no action needed" -ForegroundColor Green
                    return
                }
            }
        }
        
        # Method 2: Try using the roles endpoint to associate the user
        try {
            Write-Host "Attempting role assignment using roles endpoint..."
            $associateUrl2 = "$formattedDynamicsUrl/api/data/v9.2/roles($RoleId)/systemuserroles_association/`$ref"
            $body2 = @{
                "@odata.id" = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)"
            } | ConvertTo-Json
            
            Write-Host "POST URL: $associateUrl2"
            Write-Host "Request Body: $body2"
            
            Invoke-RestMethod -Uri $associateUrl2 -Method POST -Headers $headers -Body $body2 -ErrorAction Stop
            Write-Host "Successfully assigned security role using roles endpoint" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Method 2 failed: $($_.Exception.Message)"
        }
        
        # Method 3: Try using the Associate action (alternative approach)
        try {
            Write-Host "Attempting role assignment using Associate action..."
            $associateActionUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/Microsoft.Dynamics.CRM.Associate"
            $associateBody = @{
                target = @{
                    "@odata.id" = "$formattedDynamicsUrl/api/data/v9.2/roles($RoleId)"
                }
                relationship = "systemuserroles_association"
            } | ConvertTo-Json -Depth 3
            
            Write-Host "POST URL: $associateActionUrl"
            Write-Host "Request Body: $associateBody"
            
            Invoke-RestMethod -Uri $associateActionUrl -Method POST -Headers $headers -Body $associateBody -ErrorAction Stop
            Write-Host "Successfully assigned security role using Associate action" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Method 3 failed: $($_.Exception.Message)"
        }
        
        # Method 4: Try using systemuserroles collection directly (POST method)
        try {
            Write-Host "Attempting role assignment using systemuserroles collection POST..."
            $rolesCollectionUrl = "$formattedDynamicsUrl/api/data/v9.2/systemuserroles"
            $rolesBody = @{
                "systemuserid@odata.bind" = "/systemusers($UserId)"
                "roleid@odata.bind" = "/roles($RoleId)"
            } | ConvertTo-Json
            
            Write-Host "POST URL: $rolesCollectionUrl"
            Write-Host "Request Body: $rolesBody"
            
            Invoke-RestMethod -Uri $rolesCollectionUrl -Method POST -Headers $headers -Body $rolesBody -ErrorAction Stop
            Write-Host "Successfully assigned security role using systemuserroles collection POST" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Method 4 failed: $($_.Exception.Message)"
        }
        
        # Method 5: Try using AddUserToRoleRequest action (CRM specific)
        try {
            Write-Host "Attempting role assignment using AddUserToRoleRequest action..."
            $addUserToRoleUrl = "$formattedDynamicsUrl/api/data/v9.2/AddUserToRole"
            $addUserBody = @{
                UserId = $UserId
                RoleId = $RoleId
            } | ConvertTo-Json
            
            Write-Host "POST URL: $addUserToRoleUrl"
            Write-Host "Request Body: $addUserBody"
            
            Invoke-RestMethod -Uri $addUserToRoleUrl -Method POST -Headers $headers -Body $addUserBody -ErrorAction Stop
            Write-Host "Successfully assigned security role using AddUserToRoleRequest action" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Method 5 failed: $($_.Exception.Message)"
        }
        
        # Method 6: Try alternative association format
        try {
            Write-Host "Attempting role assignment using alternative association format..."
            $altAssociateUrl = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association"
            $altBody = @{
                "@odata.id" = "$formattedDynamicsUrl/api/data/v9.2/roles($RoleId)"
            } | ConvertTo-Json
            
            # Add specific headers for this method
            $altHeaders = $headers.Clone()
            $altHeaders["If-None-Match"] = "*"  # Prevent conflicts
            
            Write-Host "POST URL: $altAssociateUrl"
            Write-Host "Request Body: $altBody"
            
            Invoke-RestMethod -Uri $altAssociateUrl -Method POST -Headers $altHeaders -Body $altBody -ErrorAction Stop
            Write-Host "Successfully assigned security role using alternative association format" -ForegroundColor Green
            return
        }
        catch {
            Write-Warning "Method 6 failed: $($_.Exception.Message)"
        }
        
        # If all methods fail, throw a comprehensive error
        throw "All 6 role assignment methods failed. Please check service principal permissions and role configuration."
        
    } catch {
        Write-Error "Failed to assign security role: $($_.Exception.Message)"
        
        # Enhanced error reporting
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDescription = $_.Exception.Response.StatusDescription
            Write-Error "HTTP Status: $statusCode - $statusDescription"
            
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Error "Error response body: $errorBody"
                
                # Parse common Power Platform errors
                if ($errorBody -like "*insufficient privileges*") {
                    Write-Error "TROUBLESHOOTING: The service principal lacks sufficient privileges to assign security roles."
                    Write-Error "Required fixes:"
                    Write-Error "1. Ensure the service principal has 'System Administrator' role or equivalent"
                    Write-Error "2. Verify the service principal can manage user security roles"
                    Write-Error "3. Check if the target role can be assigned by the service principal"
                }
                elseif ($errorBody -like "*SecurityRole*" -or $errorBody -like "*privilege*") {
                    Write-Error "TROUBLESHOOTING: Security role assignment privilege issue detected."
                    Write-Error "The service principal may not have permission to assign the '$userRole' role."
                }
                elseif ($statusCode -eq 400) {
                    Write-Error "TROUBLESHOOTING: Bad Request (400) - Common causes:"
                    Write-Error "1. Invalid User ID: $UserId"
                    Write-Error "2. Invalid Role ID: $RoleId" 
                    Write-Error "3. Malformed request URL or body"
                    Write-Error "4. The role cannot be assigned to this user type"
                    Write-Error "5. Business unit mismatch between user and role"
                    Write-Error "6. The service principal lacks 'Assign Role' privilege"
                    Write-Error "7. The target user may be disabled or in wrong state"
                }
                elseif ($statusCode -eq 404) {
                    Write-Error "TROUBLESHOOTING: Not Found (404) - Common causes:"
                    Write-Error "1. The API endpoint is not available in this Dynamics version"
                    Write-Error "2. The service principal lacks access to the systemuserroles entity"
                    Write-Error "3. The Microsoft.Dynamics.CRM.Associate action is not supported"
                    Write-Error "4. Invalid entity relationship name"
                }
                elseif ($statusCode -eq 403) {
                    Write-Error "TROUBLESHOOTING: Forbidden (403) - Permission denied"
                    Write-Error "1. Service principal needs 'prvAssignRole' privilege"
                    Write-Error "2. Service principal needs write access to systemuserroles entity"
                    Write-Error "3. Check if the service principal can modify user security settings"
                }
            } catch {
                Write-Warning "Could not read detailed error response: $($_.Exception.Message)"
            }
        }
        
        # Additional troubleshooting information
        Write-Error "CONFIGURATION DETAILS:"
        Write-Error "- User ID: $UserId"
        Write-Error "- Role ID: $RoleId"
        Write-Error "- Dynamics URL: $formattedDynamicsUrl"
        Write-Error "- Service Principal Client ID: $env:CLIENT_ID"
        
        Write-Error "VERIFICATION STEPS:"
        Write-Error "1. Verify the service principal has System Administrator role in Power Platform"
        Write-Error "2. Check that the role '$userRole' exists and is active"
        Write-Error "3. Ensure the user and role are in compatible business units"
        Write-Error "4. Confirm the service principal can read/write systemuserroles entity"
        Write-Error "5. Check if the service principal has 'prvAssignRole' privilege specifically"
        Write-Error "6. Verify the target user is enabled and not in a disabled state"
        Write-Error "7. Ensure both user and role are in the same or compatible business units"
        Write-Error ""
        Write-Error "MANUAL VERIFICATION COMMANDS:"
        Write-Error "1. Test role query: GET $formattedDynamicsUrl/api/data/v9.2/roles($RoleId)"
        Write-Error "2. Test user query: GET $formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)"
        Write-Error "3. Check existing roles: GET $formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)/systemuserroles_association"
        Write-Error "4. Check service principal permissions: Use Power Platform admin center"
        
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
        
        Write-Host "PATCH URL: $updateUrl"
        Write-Host "Request Body: $body"
        
        Invoke-RestMethod -Uri $updateUrl -Method PATCH -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully updated user business unit" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to update business unit: $($_.Exception.Message)"
        
        # Enhanced error reporting
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDescription = $_.Exception.Response.StatusDescription
            Write-Error "HTTP Status: $statusCode - $statusDescription"
            
            if ($statusCode -eq 400) {
                Write-Error "TROUBLESHOOTING: Bad Request (400) - Common causes:"
                Write-Error "1. Invalid User ID: $UserId"
                Write-Error "2. Invalid Business Unit ID: $BusinessUnitId"
                Write-Error "3. The user cannot be moved to this business unit"
                Write-Error "4. Business unit change restrictions in place"
            }
            elseif ($statusCode -eq 403) {
                Write-Error "TROUBLESHOOTING: Forbidden (403) - Permission denied"
                Write-Error "1. Service principal needs permission to modify user business units"
                Write-Error "2. Check if the service principal has System Administrator role"
            }
            
            try {
                $errorStream = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($errorStream)
                $errorBody = $reader.ReadToEnd()
                Write-Error "Error response body: $errorBody"
            } catch {
                Write-Warning "Could not read detailed error response: $($_.Exception.Message)"
            }
        }
        
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
        
        # Associate user with team
        $associateUrl = "$formattedDynamicsUrl/api/data/v9.2/teams($TeamId)/teammembership_association/`$ref"
        $body = @{
            "@odata.id" = "$formattedDynamicsUrl/api/data/v9.2/systemusers($UserId)"
        } | ConvertTo-Json
        
        Write-Host "POST URL: $associateUrl"
        Write-Host "Request Body: $body"
        
        Invoke-RestMethod -Uri $associateUrl -Method POST -Headers $headers -Body $body -ErrorAction Stop
        Write-Host "Successfully added user to team" -ForegroundColor Green
        
    } catch {
        Write-Error "Failed to add user to team: $($_.Exception.Message)"
        
        # Enhanced error reporting
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 400) {
                Write-Error "TROUBLESHOOTING: Bad Request (400) - User may already be in team or invalid IDs"
            }
            elseif ($statusCode -eq 403) {
                Write-Error "TROUBLESHOOTING: Forbidden (403) - Service principal lacks team management permissions"
            }
        }
        
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
        
        # Remove user from team
        $removeUrl = "$formattedDynamicsUrl/api/data/v9.2/teams($TeamId)/teammembership_association/$UserId/`$ref"
        Write-Host "DELETE URL: $removeUrl"
        
        Invoke-RestMethod -Uri $removeUrl -Method DELETE -Headers $headers -ErrorAction Stop
        Write-Host "Successfully removed user from team" -ForegroundColor Green
        
    } catch {
        Write-Warning "Failed to remove user from team: $($_.Exception.Message)"
        
        # Don't throw for cleanup operations - log warning and continue
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 404) {
                Write-Host "User was not in team (404 Not Found) - no action needed" -ForegroundColor Yellow
            }
        }
    }
}

# Install Node.js on the target machine - Linux compatible version
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
    
    # Check if running on Linux (since you mentioned Linux machine)
    if ($IsLinux -or $env:OS -notlike "*Windows*") {
        Write-Host "Installing Node.js on Linux using package manager..."
        try {
            # Try different package managers
            if (Get-Command apt-get -ErrorAction SilentlyContinue) {
                Write-Host "Using apt-get to install Node.js..."
                & sudo apt-get update
                & sudo apt-get install -y nodejs npm
            } elseif (Get-Command yum -ErrorAction SilentlyContinue) {
                Write-Host "Using yum to install Node.js..."
                & sudo yum install -y nodejs npm
            } else {
                Write-Warning "No supported package manager found. Node.js installation may fail."
                Write-Host "Please install Node.js manually or ensure it's available in the container."
            }
            
            # Verify installation
            $installedVersion = & node --version 2>$null
            if ($installedVersion) {
                Write-Host "Node.js successfully installed. Version: $installedVersion"
            } else {
                throw "Node.js installation verification failed"
            }
        } catch {
            Write-Error "Failed to install Node.js on Linux: $($_.Exception.Message)"
            throw
        }
    } else {
        # Windows installation logic
        Write-Host "Installing Node.js version $NodeVersion on Windows..."
        
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
        $testCommand += " --reporter=list,html"  # Use list reporter for live output and HTML for detailed report
        
        # Add test pattern if specified
        if (![string]::IsNullOrWhiteSpace($TestPattern)) {
            $testCommand += " $TestPattern"
        }
        
        # Add additional flags for better debugging and performance
        $testCommand += " --output=test-results" 
        $testCommand += " --max-failures=10"  # Stop after 10 failures to save time
        
        # Add extra verbose flags for better live output
        Write-Host "Adding verbose output flags for better real-time feedback..." -ForegroundColor Cyan
        $testCommand += " --reporter=html,line"  # Ensure we get detailed HTML report
        
        Write-Host "Executing command: $testCommand"
        Write-Host "Starting Playwright test execution with live output streaming..."
        
        # Execute the tests with live output streaming
        try {
            Write-Host "Executing: $testCommand" -ForegroundColor Cyan
            Write-Host "Working Directory: $playwrightPath" -ForegroundColor Cyan
            Write-Host "============================================" -ForegroundColor Green
            Write-Host "LIVE TEST OUTPUT:" -ForegroundColor Green
            Write-Host "============================================" -ForegroundColor Green
            
            # Change to playwright directory for execution
            Push-Location $playwrightPath
            
            # Execute with live output streaming using cmd /c
            $testExitCode = 0
            try {
                # Method 1: Use cmd /c to properly handle npx and stream output
                Write-Host "Using cmd /c method for live output streaming..." -ForegroundColor Gray
                & cmd /c "$testCommand 2>&1"
                $testExitCode = $LASTEXITCODE
            } catch {
                Write-Host "cmd /c method failed, trying alternative approach..." -ForegroundColor Yellow
                try {
                    # Method 2: Direct Invoke-Expression as fallback
                    Write-Host "Using Invoke-Expression method as fallback..." -ForegroundColor Gray
                    Invoke-Expression $testCommand
                    $testExitCode = $LASTEXITCODE
                } catch {
                    Write-Host "Exception during test execution: $($_.Exception.Message)" -ForegroundColor Red
                    $testExitCode = 1
                }
            }
            
            # Return to previous location
            Pop-Location
            
            Write-Host "============================================" -ForegroundColor $(if ($testExitCode -eq 0) { "Green" } else { "Red" })
            Write-Host "Test execution completed with exit code: $testExitCode" -ForegroundColor $(if ($testExitCode -eq 0) { "Green" } else { "Red" })
            Write-Host "============================================" -ForegroundColor $(if ($testExitCode -eq 0) { "Green" } else { "Red" })
        } catch {
            Write-Error "Failed to execute Playwright tests: $($_.Exception.Message)"
            Write-Host "Error details: $($_.Exception)" -ForegroundColor Red
            $testExitCode = 1
        }
        
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
$playwrightVersion = Get-VstsInput -Name 'playwrightVersion'

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
            
            # If business unit is also being changed, do that first to ensure compatibility
            if (![string]::IsNullOrWhiteSpace($businessUnit)) {
                Write-Host "Business unit change detected - updating business unit before role assignment..."
                $businessUnitId = Get-PowerPlatformBusinessUnitId -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -BusinessUnitName $businessUnit
                Update-UserBusinessUnit -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId -BusinessUnitId $businessUnitId
                Write-Host "Business unit updated - proceeding with role assignment..."
            }
            
            Add-UserSecurityRole -DynamicsUrl $dynamicsUrl -AccessToken $accessToken -UserId $userId -RoleId $roleId
        }
        
        if (![string]::IsNullOrWhiteSpace($businessUnit) -and [string]::IsNullOrWhiteSpace($userRole)) {
            # Only update business unit if role assignment didn't already handle it
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

# Use hardcoded default repository URL
$repositoryUrl = "https://github.com/itweedie/playwrightOnPowerPlatform.git"

# Call function with version parameter
Clone-PlaywrightRepository -RepositoryUrl $repositoryUrl -Branch $playwrightVersion

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
    
    # The function returns an exit code, but we should check if it's null or valid
    if ($null -eq $testResults) {
        $testResults = 1  # Default to failure if no result returned
    }

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
                    $headers = @{
                        "Authorization" = "Bearer $accessToken"
                        "OData-MaxVersion" = "4.0"
                        "OData-Version" = "4.0"
                        "Accept" = "application/json"
                    }

                    # Ensure the dynamics URL is properly formatted with https://
                    $cleanDynamicsUrl = $dynamicsUrl
                    if (-not $cleanDynamicsUrl.StartsWith("https://") -and -not $cleanDynamicsUrl.StartsWith("http://")) {
                        $cleanDynamicsUrl = "https://$cleanDynamicsUrl"
                    }
                    
                    $removeRoleUrl = "$cleanDynamicsUrl/api/data/v9.2/systemusers($userId)/systemuserroles_association/$roleId/`$ref"
                    Write-Host "Sending DELETE request to URL: $removeRoleUrl" -ForegroundColor Yellow
                    Write-Host "Headers: $($headers | Out-String)" -ForegroundColor Yellow

                    Invoke-RestMethod -Uri $removeRoleUrl -Method DELETE -Headers $headers -ErrorAction Stop
                    Write-Host "Successfully removed security role: $userRole" -ForegroundColor Green
                } catch {
                    Write-Warning "Failed to remove security role: $($_.Exception.Message)"
                    if ($_.Exception.Response -ne $null) {
                        $responseContent = $_.Exception.Response.GetResponseStream()
                        if ($responseContent -ne $null) {
                            $reader = New-Object System.IO.StreamReader($responseContent)
                            $responseBody = $reader.ReadToEnd()
                            Write-Warning "Response Body: $responseBody"
                        }
                    }
                }
            }
            
            # Remove from team if it was assigned
            if (![string]::IsNullOrWhiteSpace($team) -and $teamId) {
                Write-Host "Note: Team assignment can not be cleaned up only reassigned."
            }
            
            # Note: Business unit changes are typically not reverted in cleanup as they may affect user's core access
            if (![string]::IsNullOrWhiteSpace($businessUnit)) {
                Write-Host "Note: Business unit assignment can not be cleaned up only reassigned."
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