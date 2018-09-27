package com.ads.controller;

import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.servlet.ModelAndView;

import java.util.Locale;
import java.util.ResourceBundle;

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

    public static void main(String[] args) {
        Locale locale = new Locale("zh", "CN");
        String displayName = locale.getDisplayName();
        System.out.println(displayName);

        ResourceBundle message = ResourceBundle.getBundle("message", locale);
    }
}
