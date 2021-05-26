//
//  NetTool.swift
//  LeMessage
//
//  Created by Rowling on 2020/3/9.
//  Copyright © 2020 Rowling. All rights reserved.
//

import Foundation
import Alamofire
import HandyJSON
import SwiftyJSON
import RxSwift

public typealias resp<T> = (_ data : ResponseModel<T>)->()

public struct ResponseModel<T> : HandyJSON {
    var message = "网络出错"
    var data : T?
    var code : ModelCode = ModelCode.netBad
    var sysTime : TimeInterval = 0
    var realResp : Any?
    public init(){}
    mutating public func mapping(mapper: HelpingMapper) {
        mapper <<<
            self.code <-- TransformOf<ModelCode, Int>(fromJSON: { (num) -> ModelCode? in
                if let num = num {
                    switch (num) {
                    case 0:
                        return ModelCode.success
                    case 200:
                        return ModelCode.success
                    default:
                        return ModelCode.init(rawValue: num)
                    }
                }
                return ModelCode.netBad
            }, toJSON: { (theCode) -> Int? in
                if let theCode = theCode {
                    return theCode.rawValue
                }
                return -1
            })
    }
}

public enum ModelCode: Int, HandyJSONEnum {
    case success = 0
    case netBad = -1
    case missionInvalid = 1
    func description() -> String {
        switch self {
        case .success: return "成功"
        case .netBad: return "网络出错"
        case .missionInvalid : return "任务已完成"
        }
    }
}

public enum ZMNetStatus {
    /**未知网络*/
    case unkown
    /**无网络*/
    case notReachable
    /**wifi*/
    case WIFI
    /**蜂窝*/
    case WWAN
}


open class ZMNetManager {
    static let shared = ZMNetManager()
    var apiprovider : ZMApiProvider?
    /**网络监听管理类*/
    private let netAbility = NetworkReachabilityManager(host: "www.baidu.com")
    /**网络状态监听*/
    let netStauts = ReplaySubject<ZMNetStatus>.create(bufferSize: 1)
    
//    static let sharedSessionManager: Alamofire.SessionManager = {
//        let configuration = URLSessionConfiguration.default
//        configuration.timeoutIntervalForRequest = 15
//        return Alamofire.SessionManager(configuration: configuration)
//    }()
    
    func badResponse<T>(realResp : Any?,message:String) -> ResponseModel<T> {
        var r = ResponseModel<T>()
        r.message = message
        r.realResp = realResp
        r.code = .netBad
        return r
    }
    
    func Request<T>(url : String ,
                    Method : HTTPMethod ,
                    param : [String : Any] ,
                    httpHeaders : HTTPHeaders?,
                    rawData : Bool = false,
                    callBack :@escaping resp<T>) -> DataRequest? {
        
        guard let wholeUrl = URL(string:url) else {
            return nil
        }
        
        print("请求地址：------->\(wholeUrl)\n请求参数:")
        for (str,vaule) in param {
            print("\(str):\(vaule)")
        }
        print("header:\n")
        var headers : HTTPHeaders = [
        "Content-Type": "application/json;charset=UTF-8",
        "Accept": "application/json",
        ]
        if let httpHeaders = httpHeaders {
            headers = httpHeaders
        }
        print(headers)
        
        var encoding : ParameterEncoding = URLEncoding.queryString
        if (headers["Content-Type"] ?? "").contains("application/json") {
            encoding = JSONEncoding.default
        }
    
        let request = AF.request(wholeUrl, method: Method, parameters: param, encoding: encoding, headers: headers).responseJSON { response in
            switch response.result {
                case .success(let vaule):
                    guard let dict = vaule as? Dictionary<String, Any> else {
                        callBack(ResponseModel())
                        return}
                    let j = JSON(dict)
                    print("请求结果：------->\(String(describing: wholeUrl))\n")
                    print(j)
                    if rawData {
                        var rs = ResponseModel<T>()
                        if let dict = dict as? T {
                            rs.code = .success
                            rs.data = dict
                        } else {
                            rs.code = .netBad
                            rs.message = "App解析出错"
                        }
                        rs.realResp = dict
                        callBack(rs)
                    } else {
                        guard var data = JSONDeserializer<ResponseModel<T>>.deserializeFrom(dict: dict) else {
                            var rs = ResponseModel<T>()
                            rs.code = .netBad
                            rs.message = "App解析出错"
                            rs.realResp = dict
                            callBack(rs)
                            return}
                        data.realResp = dict
                        callBack(data)
                    }
                    break
                case .failure(let error):
                    print("请求结果：------->\(String(describing: wholeUrl))\n")
                    print(error)
                    callBack(self.badResponse(realResp: error.errorDescription, message: error.errorDescription ?? ""))
                    break
            }
        }
        return request
    }
    
    func requestUpload<T>(url : String , data: [Data],httpHeaders : HTTPHeaders?, callBack: @escaping resp<T>) -> UploadRequest?{
       let request = requestFileUpload(url: url, mimeType: "image/png", paramName: "picture", files: [(String, Data)](), httpHeaders: httpHeaders,multipartFormData:{ multipartFormData in
            for i in 0..<data.count{
                //设置图片的名字
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMddHHmmss"
                let string = formatter.string(from: Date())
                let filename = "\(string).png"
                multipartFormData.append(data[i], withName: "picture", fileName: filename, mimeType: "image/png")
            }
        }, callBack: callBack)
        return request
    }
    
    func requestFileUpload<T>(url : String ,mimeType : String ,paramName : String , files:[(String,Data)] ,httpHeaders : HTTPHeaders?,multipartFormData : ((MultipartFormData) -> Void)? = nil, callBack: @escaping resp<T>) -> UploadRequest? {
        
        var headers : HTTPHeaders = [
            "Content-Type": "multipart/form-data",
            "Accept": "application/json",
            ]
        if let httpHeaders = httpHeaders {
            headers = httpHeaders
        }
        
        guard let wholeUrl = URL(string:url) else {
            return nil
        }

        let reqest = AF.upload(multipartFormData: multipartFormData ?? { multipartFormData in
            for data in files{
                //设置图片的名字
                multipartFormData.append(data.1, withName: paramName, fileName: data.0, mimeType: mimeType)
            }
        }, to: wholeUrl,method: HTTPMethod.post, headers: headers).responseJSON { encodingResult in
            switch encodingResult.result {
                case .success(let value):
                    let json = JSON(value).description
                    print(json)
                    if let dict = value as? [String : AnyObject]{
                        guard var data = JSONDeserializer<ResponseModel<T>>.deserializeFrom(dict: dict) else {
                            var rs = ResponseModel<T>()
                            rs.code = .netBad
                            rs.message = "App解析出错"
                            rs.realResp = value
                            callBack(rs)
                            return}
                        data.realResp = value
                        callBack(data)
                    } else {
                        var rs = ResponseModel<T>()
                        rs.code = .netBad
                        rs.message = "App解析出错"
                        rs.realResp = value
                        callBack(rs)
                    }
                    break
                case .failure(let error):
                    print("请求结果：------->\(String(describing: wholeUrl))\n")
                    print(error)
                    callBack(self.badResponse(realResp: error.errorDescription, message: error.errorDescription ?? ""))
                    break
            }
        }
        return reqest
    }


    func getDictionaryFromJSONString(jsonString:String) ->NSDictionary{
        let jsonData:Data = jsonString.data(using: .utf8)!
        let dict = try? JSONSerialization.jsonObject(with: jsonData, options: .mutableContainers)
        if dict != nil {
            return dict as! NSDictionary
        }
        return NSDictionary()
    }
    
    //MARK:网络监听
    func setUpNetLister() {
        netAbility?.startListening(onUpdatePerforming: { [weak self] status in
            switch status {
                case .unknown:
                    self?.netStauts.onNext(.unkown)
                case .notReachable:
                    self?.netStauts.onNext(.notReachable)
                case .reachable(.cellular):
                    self?.netStauts.onNext(.WWAN)
                case .reachable(.ethernetOrWiFi):
                    self?.netStauts.onNext(.WIFI)
            }
        })
    }

}
