//
//  StravaOAuth.swift
//  StravaKit
//
//  Created by Brennan Stehling on 8/20/16.
//  Copyright © 2016 SmallSharpTools LLC. All rights reserved.
//

import Foundation

/** Authorization Completed Notification */
public let StravaAuthorizationCompletedNotification : String = "StravaAuthorizationCompleted"

/** Status Key */
public let StravaStatusKey: String = "status"
/** Error Key */
public let StravaErrorKey: String = "error"
/** Success Value */
public let StravaStatusSuccessValue: String = "success"
/** Failure Value */
public let StravaStatusFailureValue: String = "failure"

internal enum OAuthResourcePath: String {
    case RequestAccess = "/oauth/authorize"
    case TokenExchange = "/oauth/token"
    case Deauthorization = "/oauth/deauthorize"
}

/**
 OAuth Scopes

 - Public: Default, private activities are not returned, privacy zones are respected in stream requests.
 - Write: Modify activities, upload on the user’s behalf.
 - Private: View private activities and data within privacy zones.
 - PrivateWrite: Both ‘view_private’ and ‘write’ access.
 */
public enum OAuthScope: String {
    case Public = "public"
    case Write = "write"
    case Private = "view_private"
    case PrivateWrite = "view_private,write"
}

/**
 Strava OAuth extension which handles authorization actions.

 Docs: http://strava.github.io/api/v3/oauth/
 */
public extension Strava {

    /**
     Initialize clientId, clientSecret and redirectURI.
     */
    static func set(clientId clientId: String, clientSecret: String, redirectURI: String, sandbox: Bool? = nil) {
        sharedInstance.clientId = clientId
        sharedInstance.clientSecret = clientSecret
        sharedInstance.redirectURI = redirectURI
    }

    /**
     Provides URL used to initiate user login for use with a Safari View Controller.

     Docs: http://strava.github.io/api/v3/oauth/#get-authorize
     */
    static func userLogin(scope scope: OAuthScope, state: String = "") -> NSURL? {
        guard let clientId = sharedInstance.clientId,
            _ = sharedInstance.clientSecret,
            redirectURI = sharedInstance.redirectURI else { return nil }

        let parameters : JSONDictionary = [
            "client_id" : clientId,
            "response_type" : "code",
            "redirect_uri" : redirectURI,
            "scope" : scope.rawValue,
            "state" : state,
            "approval_prompt" : "force"
        ]

        let path = OAuthResourcePath.RequestAccess.rawValue
        let URL = urlWithString("\(StravaBaseURL)/\(path)", parameters: parameters)
        return URL
    }

    /**
     Handles the URL given to AppDelegate.
     */
    static func openURL(URL: NSURL, sourceApplication: String?) -> Bool {
        guard let _ = sharedInstance.clientId,
            _ = sharedInstance.clientSecret else {
                return false
        }

        guard let sa = sourceApplication where sa == "com.apple.SafariViewService",
            let uri = sharedInstance.redirectURI,
            let _ = URL.absoluteString.rangeOfString(uri) else {
                return false
        }

        var error: NSError? = nil

        // The user can tap the cancel button which results in an access denied error.
        // Example: stravademo://localhost/oauth/signin?state=&error=access_denied

        if let errorValue = queryStringValue(URL, name: "error") {
            error = Strava.error(.RemoteError, reason: "Remote Error: \(errorValue)")
            notifyAuthorizationCompleted(false, error: error)
        }
        else if let code = queryStringValue(URL, name: "code") {
            exchangeTokenWithCode(code) { (success, error) in
                notifyAuthorizationCompleted(success, error: error)
            }
        }

        return true
    }

    /**
     Deauthorizes Strava access token.

     Docs: http://strava.github.io/api/v3/oauth/#deauthorize
     */
    static func deauthorize(completionHandler: ((success: Bool, error: NSError?) -> ())?) {
        let path = OAuthResourcePath.Deauthorization.rawValue

        request(.POST, authenticated: true, path: path, params: nil) { (response, error) in
            if let error = error {
                dispatch_async(dispatch_get_main_queue()) {
                    completionHandler?(success: false, error: error)
                }
                return
            }

            sharedInstance.accessToken = nil
            sharedInstance.athlete = nil
            sharedInstance.deleteAccessData()
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler?(success: true, error: nil)
            }
        }
    }

    // MARK: - Internal Functions -

    /**
     Exchanges code with the OAuth provider for the Access Token.

     Docs: http://strava.github.io/api/v3/oauth/#post-token
     */
    internal static func exchangeTokenWithCode(code: String, completionHandler: ((success: Bool, error: NSError?) -> ())?) {
        guard let clientId = sharedInstance.clientId,
            clientSecret = sharedInstance.clientSecret else {
                let error = Strava.error(.MissingCredentials, reason: "Missing Credentials")
                dispatch_async(dispatch_get_main_queue()) {
                    completionHandler?(success: false, error: error)
                }
                return
        }

        let path = OAuthResourcePath.TokenExchange.rawValue
        let params: JSONDictionary = [
            "client_id" : clientId,
            "client_secret" : clientSecret,
            "code" : code
        ]

        request(.POST, authenticated: false, path: path, params: params) { (response, error) in
            if let error = error {
                dispatch_async(dispatch_get_main_queue()) {
                    completionHandler?(success: false, error: error)
                }
                return
            }

            guard let response = response,
                let accessToken = response["access_token"] as? String,
                let athleteDictionary = response["athlete"] as? JSONDictionary else {
                    let error = Strava.error(.InvalidResponse, reason: "Invalid Response")
                    dispatch_async(dispatch_get_main_queue()) {
                        completionHandler?(success: false, error: error)
                    }
                    return
            }

            sharedInstance.accessToken = accessToken
            sharedInstance.athlete = Athlete(dictionary: athleteDictionary)
            sharedInstance.storeAccessData()
            assert(sharedInstance.athlete != nil, "Athlete is required")
            dispatch_async(dispatch_get_main_queue()) {
                completionHandler?(success: true, error: nil)
            }
        }
    }

    internal static func notifyAuthorizationCompleted(success: Bool, error: NSError?) {
        var userInfo: JSONDictionary = [:]
        userInfo[StravaStatusKey] = success ? StravaStatusSuccessValue : StravaStatusFailureValue
        if let error = error {
            userInfo[StravaErrorKey] = error
        }
        let nc = NSNotificationCenter.defaultCenter()
        let name = StravaAuthorizationCompletedNotification
        dispatch_async(dispatch_get_main_queue()) {
            nc.postNotificationName(name, object: nil, userInfo: userInfo)
        }
    }

    internal static func queryStringValue(URL: NSURL, name: String) -> String? {
        return NSURLComponents(URL: URL, resolvingAgainstBaseURL: false)?.queryItems?.filter({ $0.name == name }).first?.value
    }
    
}
