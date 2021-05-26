//
//  APIManager.swift
//  LeMessage
//
//  Created by Rowling on 2020/4/14.
//  Copyright © 2020 Rowling. All rights reserved.
//

import UIKit
import Alamofire
import HandyJSON
import RxSwift

public protocol ZMApiProvider{
    /**根路径 Url*/
    func BaseUrl() -> String
    /**请求子路径，请求方式，参数*/
    func urlAndMthodAndParam() -> (String,ZMHTTPMethod,[String : Any])
    /**请求头*/
    func HTTPHeader() -> [String : String]?
    /** file 上传,不是就传nil*/
    func UpLoadData() -> [Data]?
    /** 参数在body中，不是就传nil*/
    func ParamInBody() -> Bool
    
    func filterResponseData<T>(resp : ResponseModel<T>) -> ResponseModel<T>
    
    func dataName() -> (String,String,[(String,Data)])?
    /**不加工原始返回数据，直接以json形式放在resp 的 data 中*/
    func rawData() -> Bool
    /**只能单次请求*/
    func singleRequest() -> Bool
}

public enum ZMHTTPMethod : String {
    case post = "POST"
    case get = "GET"
    case delete = "DELETE"
    case put = "PUT"
}

public extension ZMApiProvider {
    func filterResponseData<T>(resp : ResponseModel<T>) -> ResponseModel<T> {
        return resp
    }
    
    func dataName() -> (String,String,[(String,Data)])? {
        return nil
    }
    
    func rawData() -> Bool {
        return false
    }
    
    func singleRequest() -> Bool {
        return false
    }
}

/// API rx 扩展
public extension ZMApiProvider {
    /**rx 请求*/
    func rxRequest<T>(type:T.Type) -> Observable<T> {
        let obable = Observable<T>.create { (obser) -> Disposable in
            let dis = ZMAPIManage<T>.rxSendRequest(self).subscribe(onNext:{ resp in
                if resp.code == .success, let data = resp.data {
                    obser.onNext(data)
                    obser.onCompleted()
                }
                else {
                    let e = NSError(domain: resp.message, code: resp.code.rawValue)
                    obser.onError(e)
                }
            })
            return dis
        }
        return obable
    }
}

// 主体请求方式
public struct ZMAPIManage<T> {
    @discardableResult
    func sendReqeust(method : ZMApiProvider , callBack: @escaping resp<T> )  -> DataRequest?  {
        guard let parsed = parseApi(method) else {
            return nil
        }
        return netmanagerRequest(parsed: parsed, method: method, callBack: callBack)
    }
    
    func rxSendRequest(method : ZMApiProvider)  -> Observable<ResponseModel<T>>  {
        let ob = Observable<ResponseModel<T>>.create { (ob) -> Disposable in
            var task : DataRequest?
            guard let parsed = self.parseApi(method) else {
                ob.onCompleted()
                return Disposables.create {
                    task?.cancel()
                }
            }
            
            let thisBlock : resp<T> = {
                       data in
                ob.onNext(data)
                ob.onCompleted()
            }
            
            task = netmanagerRequest(parsed: parsed, method: method, callBack: thisBlock)
            let dis = Disposables.create {
                task?.cancel()
            }
            return dis
        }
        return ob
    }
    
    // 调用netmanager发起请求
    func netmanagerRequest(parsed : ZMAPIParsedModel,method : ZMApiProvider,callBack : @escaping resp<T>) -> DataRequest? {
        let thisBlock : resp<T> = {
                   data in
            // 请求成功后移除缓存
            if parsed.singleRequest {
                RequestCacheManager.shard.removeRequestCache(key: parsed.url + parsed.httpMethod.rawValue)
            }
            // 执行过滤返回值的方法
            let resp = ZMAPIAdapter.shard.filterResponseData(api: method,apiParsedModel : parsed, resp: data)
            callBack(resp)
        }
        
        var task : DataRequest?
        
        let httpMethod = HTTPMethod.init(rawValue: parsed.httpMethod.rawValue)
        var httpHeader = HTTPHeaders()
        if let headers = parsed.headers {
            for dic in headers {
                httpHeader.add(name: dic.key, value: dic.value)
            }
        }
        if let dName = method.dataName() {
            task = ZMNetManager.shared.requestFileUpload(url: parsed.url, mimeType: dName.0, paramName: dName.1, files: dName.2, httpHeaders: httpHeader, callBack: thisBlock)
        } else if method.UpLoadData() != nil {
            task = ZMNetManager.shared.requestUpload(url: parsed.url, data: method.UpLoadData()!,httpHeaders: httpHeader,callBack: thisBlock)
        } else  {
            task = ZMNetManager.shared.Request(url: parsed.url, Method: httpMethod, param:parsed.param ,httpHeaders: httpHeader,rawData : parsed.rawData,callBack: thisBlock)
        }
        return task
    }
    
    // 解析枚举请求,返回空表示不通过，所以就应该终止请求
    func parseApi(_ method : ZMApiProvider) -> ZMAPIParsedModel? {
        let url = method.BaseUrl() + method.urlAndMthodAndParam().0
        let httpMethod = method.urlAndMthodAndParam().1
        
        // 判断是否只能单次请求
        if method.singleRequest() {
            if RequestCacheManager.shard.requestCache[url + httpMethod.rawValue] == nil {
                RequestCacheManager.shard.requestCache[url + httpMethod.rawValue] = "1"
            } else {
                return nil
            }
        }
        
        // 实际解析参数
        let realParsed = ZMAPIParsedModel(url: url,
                                         httpMethod: httpMethod,
                                         param: method.urlAndMthodAndParam().2,
                                         headers: method.HTTPHeader(),
                                         rawData: method.rawData(),
                                         singleRequest: method.singleRequest())
        
        let fileterParsed = ZMAPIAdapter.shard.filterRequest(api: method, parsedModel: realParsed)
        return fileterParsed
    }
    
    /// rx 类方法请求
    static func rxSendRequest(_ method : ZMApiProvider) -> Observable<ResponseModel<T>> {
        ZMAPIManage<T>().rxSendRequest(method: method)
    }
    
    static func rxSendRequestThen(_ method : ZMApiProvider) -> Observable<T> {
        ZMAPIManage<T>().rxSendRequest(method: method).zmResultDeal(T.self)
    }
}

public struct ZMAPIParsedModel {
    var url : String
    var httpMethod : ZMHTTPMethod
    var param : [String : Any]
    var headers : [String : String]?
    var rawData : Bool
    var singleRequest : Bool
}

extension Observable {
    func zmResultDeal<T>(_ type : T.Type) -> Observable<T> {
        let ob = self as! Observable<ResponseModel<T>>
        return ob.filter({
                            $0.code == .success
            
        }).compactMap({$0.data})
    }
}

open class RequestCacheManager {
    static let shard = RequestCacheManager()
    private init(){}
    var requestCache = [String : String]()
    func removeRequestCache(key : String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.requestCache.removeValue(forKey: key)
        }
    }
}

public protocol ListRequestObjct : NSObjectProtocol {
    associatedtype T
    var listData : [T] {get set}
    var page : Int {get set}
    var pageSize : Int {get set}
    var refreshScrollView : UIScrollView {get}
    func listRequest(_ resp : ResponseModel<[T]>)
}


public protocol ZMAPIConfig : NSObjectProtocol {
    func filterResponseData<T>(api : ZMApiProvider,apiParsedModel : ZMAPIParsedModel, resp : ResponseModel<T>) -> ResponseModel<T>
    
    func filterRequest(api : ZMApiProvider,parsedModel : ZMAPIParsedModel) -> ZMAPIParsedModel
}

public extension ZMAPIConfig {
    func filterResponseData<T>(api : ZMApiProvider, resp : ResponseModel<T>) -> ResponseModel<T> {
        return resp
    }
    
    func filterRequest(api : ZMApiProvider,parsedModel : ZMAPIParsedModel) -> ZMAPIParsedModel {
        return parsedModel
    }
}

/// config
open class ZMAPIAdapter {
    static let shard = ZMAPIAdapter()
    var delegate : ZMAPIConfig?
    private init(){
        let namespace = Bundle.main.infoDictionary!["CFBundleExecutable"] as! String
        if let cls = NSClassFromString("\(namespace).ZMAPIConfigImpl") as? NSObject.Type {
            print(cls)
            let a = cls.init()
            if let d = a as? ZMAPIConfig {
                delegate = d
            }
        }
    }
    
    /// 所有请求的结果过滤器
    public func filterResponseData<T>(api : ZMApiProvider,apiParsedModel : ZMAPIParsedModel, resp : ResponseModel<T>) -> ResponseModel<T> {
        var r = resp
        if let delegate = delegate {
            r = delegate.filterResponseData(api: api,apiParsedModel:apiParsedModel, resp: resp)
        }
        return api.filterResponseData(resp: r)
    }
    
    /// 所有请求的参数过滤器
    public func filterRequest(api : ZMApiProvider,parsedModel : ZMAPIParsedModel) -> ZMAPIParsedModel {
        var r = parsedModel
        r.headers?["Content-Type"] = api.ParamInBody() ?  "application/json;charset=UTF-8" : "application/x-www-form-urlencoded"
        if let delegate = delegate {
            r = delegate.filterRequest(api: api, parsedModel: r)
        }
        return r
    }
}



