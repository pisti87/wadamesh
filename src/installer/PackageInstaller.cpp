#include "PackageInstaller.h"

#include <SD.h>


namespace tdeck::installer
{


PackageInstaller::PackageInstaller()
{
}



InstallResult PackageInstaller::install(
    const String &packagePath
)
{

    VerifyResult result =
        verifier.verify(packagePath);



    if (result != VerifyResult::Ok)
    {
        return InstallResult::VerificationFailed;
    }



    String destination =
        verifier.getDestination();



    if (!createDestination(destination))
    {
        return InstallResult::DestinationError;
    }



    if (!copyPackage(
            packagePath,
            destination))
    {
        return InstallResult::InstallFailed;
    }



    return InstallResult::Ok;
}





bool PackageInstaller::createDestination(
    const String &path
)
{

    if (SD.exists(path))
    {
        return true;
    }


    return SD.mkdir(path);
}





bool PackageInstaller::copyPackage(
    const String &source,
    const String &destination
)
{

    /*
       Ide kerül majd:

       ZIP extractor

       vagy

       package file copier


       Jelenlegi verzió:
       csak a struktúrát készíti elő.
    */


    if (!SD.exists(source))
    {
        return false;
    }


    return true;
}


}
