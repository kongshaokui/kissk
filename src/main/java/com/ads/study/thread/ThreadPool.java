package com.ads.study.thread;

import java.util.HashMap;
import java.util.List;
import java.util.concurrent.*;

/**
 * @Classname ThreadPool
 * @Description TODO
 * @Created by kongshaokui
 * @Date 2019/8/5 11:32
 */
public class ThreadPool {

    /**
     * 可缓存线程池
     */
    public static void cachedPool() {
        ExecutorService executorService = Executors.newCachedThreadPool();
        for (int i = 0; i < 10; i++) {
            final int finalI = i;
            executorService.execute(new Runnable() {
                @Override
                public void run() {
                    System.out.println(Thread.currentThread().getName() + ":" + finalI);
                }
            });
        }
    }

    /**
     * 固定线程池
     * 线程池线程空闲时 不会释放资源 会一直占用一定的系统资源
     */
    public static void fixedPool() throws Exception{
        ExecutorService executorService = Executors.newFixedThreadPool(2);
        for (int i = 0; i < 1000; i++) {
            final int finalI = i;
            executorService.execute(new Runnable() {
                @Override
                public void run() {
                    System.out.println(Thread.currentThread().getName() + ":" + finalI);
                }
            });
        }
        Thread.sleep(1000 * 10);
        executorService.shutdownNow();
        System.out.println(executorService.isShutdown());
    }

    /**
     * 单一线程池
     *
     */
    public static void singlePool() throws Exception{
        ExecutorService executorService = Executors.newSingleThreadExecutor();
        for (int i = 0; i < 100; i++) {
            final int finalI = i;
            executorService.execute(new Runnable() {
                @Override
                public void run() {
                    System.out.println(Thread.currentThread().getName() + ":" + finalI);
                }
            });
        }
    }

    /**
     *  定时执行 线程池
     * @throws Exception
     */
    public static void scheduledPool() throws Exception{
        ScheduledExecutorService scheduledExecutorService = Executors.newScheduledThreadPool(2);
        for (int i = 0; i < 10; i++) {
            final int finalI = i;
            scheduledExecutorService.scheduleAtFixedRate(new Runnable() {
                @Override
                public void run() {
                    System.out.println(Thread.currentThread().getName() + ":" + finalI);
                }
            },3,10, TimeUnit.SECONDS);
        }
    }

    public static void main(String[] args) throws Exception{
        System.out.println(Integer.SIZE);
//        cachedPool();
//        fixedPool();
//        singlePool();
//        scheduledPool();

        System.out.println(1 << 30);
    }
}
