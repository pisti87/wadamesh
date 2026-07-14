#include "PackageVerifier.h"

#include <FS.h>
#include <SD.h>


namespace tdeck::installer
{


PackageVerifier::PackageVerifier()
{
}


VerifyResult PackageVerifier::verify(const String &packagePath)
{

    if (!loadPackageJson(packagePath))
    {
        return VerifyResult::PackageMissing;
    }


    if (!checkRequiredFields())
    {
        return VerifyResult::MissingField;
    }


    if (!checkDevice())
    {
        return VerifyResult::UnsupportedDevice;
    }


    if (!checkVersion())
    {
        return VerifyResult::UnsupportedVersion;
    }


    return VerifyResult::Ok;
}



bool PackageVerifier::loadPackageJson(const String &path)
{

    String fileName = path;


    if (!path.endsWith("package.json"))
    {
        fileName += "/package.json";
    }


    File file = SD.open(fileName, FILE_READ);


    if (!file)
    {
        return false;
    }


    DeserializationError error =
        deserializeJson(packageDoc, file);


    file.close();


    if (error)
    {
        return false;
    }


    packageName =
        packageDoc["name"] | "";


    packageType =
        packageDoc["type"] | "";


    destination =
        packageDoc["destination"] | "";


    version =
        packageDoc["version"] | "";


    return true;
}



bool PackageVerifier::checkRequiredFields()
{

    if (packageName.isEmpty())
        return false;


    if (packageType.isEmpty())
        return false;


    if (destination.isEmpty())
        return false;


    if (version.isEmpty())
        return false;


    return true;
}



bool PackageVerifier::checkDevice()
{

    JsonArray devices =
        packageDoc["device"];


    if (devices.isNull())
        return false;



    for (JsonVariant device : devices)
    {

        String name =
            device.as<String>();


        if (name == "tdeck")
        {
            return true;
        }

    }


    return false;
}



bool PackageVerifier::checkVersion()
{

    String framework =
        packageDoc["framework"] | "";


    if (framework.isEmpty())
    {
        return false;
    }


    // jelenlegi framework verzió
    // később ConfigManagerből jön

    String current =
        "1.0.0";


    return framework <= current;
}



String PackageVerifier::getPackageName() const
{
    return packageName;
}



String PackageVerifier::getPackageType() const
{
    return packageType;
}



String PackageVerifier::getDestination() const
{
    return destination;
}


}
