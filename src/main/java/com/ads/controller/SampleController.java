package com.ads.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.ResponseBody;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.servlet.ModelAndView;

/**
 * User: kismetkong@tcl.com
 * Date: 2018-05-15
 * Time: 10:22
 */
@Controller
public class SampleController {

    //负责处理/index.html的请求
    @RequestMapping(value = {"/" , "/index.html"})//可配置多个映射路径
    public ModelAndView home(){
        ModelAndView modelAndView = new ModelAndView();
        modelAndView.setViewName("index");
        return modelAndView;
    }
}
