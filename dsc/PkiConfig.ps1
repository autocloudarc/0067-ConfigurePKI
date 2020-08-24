Configuration PkiConfig
{
    $domainAdminCred = Get-AutomationPSCredential 'domainAdminCred'

    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName ActiveDirectoryCSDsc
    Import-DscResource -ModuleName CertificateDsc
    Import-DscResource -ModuleName xPendingReboot
    Import-DscResource -ModuleName xStorage

    Node $AllNodes.NodeName
    {
        xDisk ConfigureDataDisk
        {
            DiskId = $node.diskId
            DriveLetter = $node.diskDriveLetter
            FSLabel = $node.fsLabel
        } # end resource

        File dirPki
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirPki
            Force = $true
            DependsOn = "[xDisk]ConfigureDataDisk"
        } # end resource

        File dirDb
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirDb
            Force = $true
            DependsOn = "[File]DirPki"
        } # end resource

        File dirLog
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirLog
            Force = $true
            DependsOn = "[File]DirPki"
        } # end resource

        File dirExport
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirExport
            Force = $true
            DependsOn = "[File]DirPki"
        } # end resource

        # Install the ADCS Certificate Authority
        WindowsFeature ADCSCA
        {
            Name = 'ADCS-Cert-Authority'
            Ensure = $node.ensure
            DependsOn = @("[File]dirPki","[File]dirDb","[File]dirLog","[File]dirExport")
        } # end resource

        WindowsFeature RSAT-ADCS
        {
            Ensure = $node.ensure
            Name = "RSAT-ADCS"
            DependsOn = @('[WindowsFeature]ADCSCA')
        } # end resource

        WindowsFeature RSAT-ADCS-Mgmt
        {
            Ensure = $node.ensure
            Name = "RSAT-ADCS-Mgmt"
            DependsOn = @('[WindowsFeature]ADCSCA')
        } # end resource

        # Configure the CA as Standalone Root CA
        AdcsCertificationAuthority ConfigureCA
        {
            IsSingleInstance = $node.singleInstance
            CAType = $node.eca
            Credential = $domainAdminCred
            Ensure = $node.ensure
            CACommonName = $node.CACommonName
            CADistinguishedNameSuffix = $node.CADistinguishedNameSuffix
            CryptoProviderName = $node.cryptoProvider
            DatabaseDirectory = $node.dbPath
            HashAlgorithmName = $node.hashAlgorithm
            KeyLength = $node.keyLength
            LogDirectory = $node.logPath
            OutputCertRequestFile = $node.exportPath
            OverwriteExistingDatabase = $node.overwrite
            ValidityPeriod = $node.periodUnits
            ValidityPeriodUnits = $node.periodValue
            PsDscRunAsCredential = $node.domainAdminCred
            DependsOn = "[WindowsFeature]ADCSCA"
        } # end resource
        # https://stackoverflow.com/questions/36997392/configure-a-dsc-resource-to-restart
        xPendingReboot Reboot1
        {
            Name = "RebootServer"
            DependsOn = @("[WindowsFeature]RSAT-ADCS","[WindowsFeature]RSAT-ADCS-Mgmt")
        } # end resource
    } # end node
} # end configuration
#endregion configuration
