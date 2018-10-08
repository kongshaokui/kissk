package com.ads.study.java8.stream;

import com.ads.model.EBaiCommon;
import com.ads.study.proxy.Student;
import com.google.common.collect.Lists;
import com.google.gson.Gson;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;
import java.util.stream.Stream;

/**
 * @Classname StreamTest
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/2/1 16:30
 */
public class StreamTest {


    /**
     * 集合joining
     * @return
     */
    public static String joining(){
        List<String> l = new ArrayList(Arrays.asList("one", "two"));
        Stream<String> sl = l.stream();
        l.add("three");
        return sl.collect(Collectors.joining("-"));
    }


    public void listToMap(){
        List<Student> students = Lists.newArrayList();
        students.add(new Student("小红",12));
        students.add(new Student("小蓝",13));
        students.add(new Student("小青",15));

    }

    public static void main(String[] args) {
        String response="{\"body\":{\"errno\":1,\"error\":{\"failed_list\":[{\"error_no\":1,\"error_msg\":\"商品不存在\",\"sku_id\":\"1561019097074190\"}],\"success_list\":[]},\"data\":\"\"}," +
                "\"cmd\":\"resp.sku.online\",\"encrypt\":null,\"sign\":\"2305C0DC334671CBBF8E432C442BF832\",\"source\":\"34618\",\"ticket\":\"AD94FE8B-49C2-B747-BE6C-25DA245A6B74\",\"timestamp\":1564592075,\"version\":\"3\"}";
//        EBaiCommon eBaiCommon = JSON.parseObject(response, EBaiCommon.class);
        Gson gson = new Gson();
        EBaiCommon eBaiCommon = gson.fromJson(response, EBaiCommon.class);
        System.out.println(eBaiCommon.getBody());
    }

}
