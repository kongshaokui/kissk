package com.ads.study.thread;

import java.util.concurrent.atomic.AtomicInteger;

/**
 * @Classname Atomic
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/9/18 15:59
 */
public class Atomic {

    public static void main(String[] args) {
        AtomicInteger atomicInteger = new AtomicInteger();
        int i = atomicInteger.incrementAndGet();
        System.out.println(i);
        System.out.println(atomicInteger.intValue());
    }
}
