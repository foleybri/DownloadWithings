## Synopsis

A simple perl script to download measurement data from a withings scale via their OAuth2 API

Data is saved to an .xlsx file and contains these values (if available):
* weight
* pulse
* height
* fat free mass
* fat ratio
* fat mass weight
* BMI

It will also produce a couple of simple graphs plotting weight and BMI

## Usage

* Details of withings OAuth2 API are here: https://developer.withings.com/oauth2/
* Sign up for a withings account (if you dont have one already): https://account.withings.com/connectionuser/account\_create
* Sign up for a withings developer app: https://account.withings.com/partner/add\_oauth2
    * You need to provide a redirect\_uri which is an https url that you control
* Copy config\_example.cfg to config\_private.cfg and enter your download location, client id, consumer secret, and redirect\_uri
* Run the script: `perl DownloadWithings.pl`
* Exercise data will appear in: `backup_location`/data.xlsx

Only tested with data taken from one model of withings scale (http://www.withings.com/us/en/products/smart-body-analyzer)

## Motivation

As with most of my data that is stored with cloud providers, I like to keep a local copy.  This is to ensure I can still access my data when either I or the cloud provider is offline.  It is also nice to include this data in the standard backups of my local computer so that all my data is backed up in the same way.

## API Reference

* https://developer.withings.com/oauth2/

## Author

Brian Foley <brianf@sindar.net>
