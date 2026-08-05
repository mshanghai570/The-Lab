//
//  p12_password_check.cpp
//  feather
//
//  Created by HAHALOSAH on 8/6/24.
//

#include "openssl_tools.hpp"
#include "common.h"

#include <openssl/pem.h>
#include <openssl/cms.h>
#include <openssl/err.h>
#include <openssl/provider.h>
#include <openssl/pkcs12.h>
#include <openssl/conf.h>
#include <openssl/evp.h>
#include <openssl/x509.h>

#include <string>

using namespace std;

bool p12_password_check(NSString *file, NSString *pass) {
	const std::string strFile = [file cStringUsingEncoding:NSUTF8StringEncoding];
	const std::string strPass = [pass cStringUsingEncoding:NSUTF8StringEncoding];
	
	BIO *bio = BIO_new_file(strFile.c_str(), "rb");
	if (!bio) {
		NSLog(@"Failed to open .p12 file");
		return false;
	}
	
	OSSL_PROVIDER_load(NULL, "legacy");
	
	PKCS12 *p12 = d2i_PKCS12_bio(bio, NULL);
	BIO_free(bio);
	
	if (!p12) {
		NSLog(@"Failed to parse PKCS12");
		return false;
	}
	
	bool valid = false;
	if (PKCS12_verify_mac(p12, NULL, 0)) {
		valid = true;
	} else if (PKCS12_verify_mac(p12, strPass.c_str(), -1)) {
		valid = true;
	}
	
	PKCS12_free(p12);
	return valid;
}

// This is fucking bullshit IMO.
//
// In total, I probably wasted a total of 1.5 hours on this
// Feel free to increment the counter until someone finds a proper fix
//
// hours_wasted = 1.5
//
// TODO: FIX
void password_check_fix_WHAT_THE_FUCK(NSString *path) {
	string strProvisionFile = [path cStringUsingEncoding:NSUTF8StringEncoding];
	string strProvisionData;
	ZFile::ReadFile(strProvisionFile.c_str(), strProvisionData);
	
	BIO *in = BIO_new(BIO_s_mem());
	if (!in) return;
	
	if ((size_t)BIO_write(in, strProvisionData.data(), (int)strProvisionData.size()) != strProvisionData.size()) {
		BIO_free(in);
		return;
	}
	
	CMS_ContentInfo *cms = d2i_CMS_bio(in, NULL);
	if (cms) CMS_ContentInfo_free(cms);
	BIO_free(in);
}

void password_check_fix_WHAT_THE_FUCK_free(NSString *path) {
	string strProvisionFile = [path cStringUsingEncoding:NSUTF8StringEncoding];
	string strProvisionData;
	ZFile::ReadFile(strProvisionFile.c_str(), strProvisionData);
	
	BIO *in = BIO_new(BIO_s_mem());
	if (!in) return;
	
	if ((size_t)BIO_write(in, strProvisionData.data(), (int)strProvisionData.size()) != strProvisionData.size()) {
		BIO_free(in);
		return;
	}
	
	CMS_ContentInfo *cms = d2i_CMS_bio(in, NULL);
	if (cms) CMS_ContentInfo_free(cms);
	// free my boy
	BIO_free(in);
}
