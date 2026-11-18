set -e

zsign -k ./.sign/pkey.p12 -p 1234 -m ./.sign/development.cer -b $1 -m ./.sign/profile.mobileprovision -o ./.sign/Bootmine.signed.ipa ./Application/Bootmine.ipa
ideviceinstaller install ./.sign/Bootmine.signed.ipa