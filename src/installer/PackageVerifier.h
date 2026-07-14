#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>

namespace tdeck::installer
{

enum class VerifyResult
{
    Ok,
    PackageMissing,
    InvalidJson,
    MissingField,
    InvalidSignature,
    UnsupportedDevice,
    UnsupportedVersion
};


class PackageVerifier
{

public:

    PackageVerifier();

    VerifyResult verify(const String &packagePath);

    String getPackageName() const;

    String getPackageType() const;

    String getDestination() const;


private:

    bool loadPackageJson(const String &path);

    bool checkRequiredFields();

    bool checkDevice();

    bool checkVersion();


private:

    JsonDocument packageDoc;

    String packageName;

    String packageType;

    String destination;

    String version;

};

}
