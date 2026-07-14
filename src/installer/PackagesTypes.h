enum class PackageType
{
    Unknown,
    Plugin,
    Theme,
    Language,
    Font,
    Firmware
};

enum class InstallResult
{
    Ok,
    InvalidPackage,
    InvalidSignature,
    UnsupportedDevice,
    UnsupportedFramework,
    CopyFailed,
    AlreadyInstalled
};
