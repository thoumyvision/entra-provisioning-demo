$UserList = Import-Csv -Path 'C:\users\mwhitman\Documents\Scripts\NewUsers.csv' 

foreach ($User in $UserList) {

     $Attributes = @{

        Enabled = $true
        ChangePasswordAtLogon = $true
        Path = "OU=$($User.OU),DC=contoso,DC=local"

        Name = "$($User.First) $($User.Last)"
        DisplayName = "$($User.First) $($User.Last)"
        UserPrincipalName = "$(($User.First).substring(0,1))$($User.Last)@contoso.local"
        SamAccountName = "$(($User.First).substring(0,1))$($User.Last)"
        EmailAddress = "$(($User.First).substring(0,1))$($User.Last)@contoso.com"

        GivenName = $User.First
        Surname = $User.Last

        Company = $User.Company
        Department = $User.Department
        AccountPassword = "Summer2019!" | ConvertTo-SecureString -AsPlainText -Force
        OtherAttributes = @{proxyAddresses = ("SMTP:" + "$(($User.First).substring(0,1))$($User.Last)@contoso.com"), ("smtp:" + "$(($User.First).substring(0,1))$($User.Last)@contosoclinic.com")}

     }

    New-ADUser @Attributes

}