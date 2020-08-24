@{
    AllNodes = @(
        @{
            NodeName = 'localhost'
            dirPki = "f:\pki"
            dirDb = "f:\pki\db"
            dirLog = "f:\pki\log"
            dirExport = "f:\pki\export"
            diskId = '2'
            diskDriveLetter = 'f'
            fslabel = 'data'
            fileType = 'Directory'
            eca = 'EnterpriseRootCA'
            singleInstance = 'Yes'
            ensure = 'Present'
            CACommonName = 'pki01'
            CADistinguishedNameSuffix = 'DC=autocloudarc,DC=ddns,DC=net'
            cryptoProvider = 'RSA#Microsoft Software Key Storage Provider'
            hashAlgorithm = 'SHA256'
            keyLength = 4096
            overwrite = $true
            periodUnits = 'Years'
            periodValue = 2
         }
    )
}