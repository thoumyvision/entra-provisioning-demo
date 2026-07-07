# Department -> M365 group + license SKU map.
# Group names are illustrative; SKU part numbers are the real Microsoft values.
# The user is added to the group; the license flows via GROUP-BASED LICENSING
# (the license is assigned to the group once, in tenant config, not per user).
@{
    'Attorney'      = @{ Group = 'Attorneys-Users';     License = 'SPE_E5' }  # Microsoft 365 E5
    'Paralegal'     = @{ Group = 'Legal-Support-Users'; License = 'SPE_E3' }  # Microsoft 365 E3
    'Legal Support' = @{ Group = 'Legal-Support-Users'; License = 'SPE_E3' }
    'IT'            = @{ Group = 'IT-Staff';            License = 'SPE_E5' }
    'Finance'       = @{ Group = 'Finance-Users';       License = 'SPE_E3' }
    'Marketing'     = @{ Group = 'Marketing-Users';     License = 'SPE_E3' }
    'HR'            = @{ Group = 'HR-Users';            License = 'SPE_E3' }
}
