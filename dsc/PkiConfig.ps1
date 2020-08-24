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
            DependsOn = "[xDisk]ConfigureDataDisk"
        } # end resource

        File dirDb
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirDb
            DependsOn = "[File]DirPki"
        } # end resource

        File dirLog
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirLog
            DependsOn = "[File]DirPki"
        } # end resource

        File dirExport
        {
            Ensure = $node.ensure
            Type = $node.fileType
            DestinationPath = $node.dirExport
            DependsOn = "[File]DirPki"
        } # end resource

        # Install the ADCS Certificate Authority
        WindowsFeature ADCSCA
        {
            Name = 'ADCS-Cert-Authority'
            Ensure = $node.ensure
            DependsOn = @("[File]dirPki","[File]dirDb","[File]dirLog","[File]dirExport")
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

        WindowsFeature RSAT-ADCS
        {
            Ensure = $node.ensure
            Name = "RSAT-ADCS"
            DependsOn = @('[WindowsFeature]ADCSCA','[AdcsCertificationAuthority]ConfigureCA')
        } # end resource

        WindowsFeature RSAT-ADCS-Mgmt
        {
            Ensure = $node.ensure
            Name = "RSAT-ADCS-Mgmt"
            DependsOn = @('[WindowsFeature]ADCSCA','[AdcsCertificationAuthority]ConfigureCA')
        } # end resource

        xPendingReboot Reboot1
        {
            Name = "RebootServer"
            DependsOn = @("[WindowsFeature]RSAT-ADCS","[WindowsFeature]RSAT-ADCS-Mgmt")
        } # end resource
    } # end node
} # end configuration
#endregion configuration
