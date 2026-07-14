#pragma once

#include <Arduino.h>

#include "PackageVerifier.h"


namespace tdeck::installer
{


enum class InstallResult
{
    Ok,
    VerificationFailed,
    SourceMissing,
    DestinationError,
    InstallFailed
};



class PackageInstaller
{

public:

    PackageInstaller();


    InstallResult install(
        const String &packagePath
    );


private:

    bool createDestination(
        const String &path
    );


    bool copyPackage(
        const String &source,
        const String &destination
    );


private:

    PackageVerifier verifier;

};


}
