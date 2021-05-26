//
//  TestAPI.swift
//  ZMBaseModule
//
//  Created by Rowling on 2020/5/22.
//  Copyright © 2020 Rowling. All rights reserved.
//

import Foundation
import Alamofire
enum TestAPI{
    /**登录*/
    case login(_ mobile: String, _ code: String)
    case faliaoDetail(_ id : Int) // 发料详情
}

extension TestAPI : ZMApiProvider {
    func BaseUrl() -> String {
        return "https://m3.mindant.cn/icps"
    }
    
    func urlAndMthodAndParam() -> (String, ZMHTTPMethod, [String : Any]) {
        switch self {
            case .login:
                return ("", .get, ["jack" : "slow"])
            case .faliaoDetail(let id):
                return ("/orderInfo/detail", .get, ["id" : id])
        }
    }
    
    func HTTPHeader() -> [String:String]? {
         var headers : [String:String] = [
                "Content-Type": "application/json;charset=UTF-8",
                "Accept": "application/json",
        ]
        
        switch self {
            case .faliaoDetail:
                headers["fuck"] = "you"
            default:
                break
        }
        return headers
    }
    
    func UpLoadData() -> [Data]? {
        return nil
    }
    
    func ParamInBody() -> Bool {
        return false
    }
    
}
