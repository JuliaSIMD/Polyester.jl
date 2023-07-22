var documenterSearchIndex = {"docs":
[{"location":"","page":"Home","title":"Home","text":"CurrentModule = Polyester","category":"page"},{"location":"#Polyester","page":"Home","title":"Polyester","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"","category":"page"},{"location":"","page":"Home","title":"Home","text":"Modules = [Polyester]","category":"page"},{"location":"#Polyester.reset_threads!-Tuple{}","page":"Home","title":"Polyester.reset_threads!","text":"Polyester.reset_threads!()\n\nResets the threads used by Polyester.jl.\n\n\n\n\n\n","category":"method"},{"location":"#Polyester.@batch-Tuple{Any}","page":"Home","title":"Polyester.@batch","text":"@batch for i in Iter; ...; end\n\nEvaluate the loop on multiple threads.\n\n@batch minbatch=N for i in Iter; ...; end\n\nCreate a thread-local storage used in the loop.\n\n@batch threadlocal=init() for i in Iter; ...; end\n\nThe init function will be called at the start at each thread. threadlocal will refer to storage local for the thread. At the end of the loop, a threadlocal vector containing all the thread-local values will be available. A type can be specified with threadlocal=init()::Type.\n\nEvaluate at least N iterations per thread. Will use at most length(Iter) ÷ N threads.\n\n@batch per=core for i in Iter; ...; end\n@batch per=thread for i in Iter; ...; end\n\nUse at most 1 thread per physical core, or 1 thread per CPU thread, respectively. One thread per core will mean less threads competing for the cache, while (for example) if there are two hardware threads per physical core, then using each thread means that there are two independent instruction streams feeding the CPU's execution units. When one of these streams isn't enough to make the most of out of order execution, this could increase total throughput.\n\nWhich performs better will depend on the workload, so if you're not sure it may be worth benchmarking both.\n\nLoopVectorization.jl currently only uses up to 1 thread per physical core. Because there is some overhead to switching the number of threads used, per=core is @batch's default, so that Polyester.@batch and LoopVectorization.@tturbo work well together by default.\n\nThreads are not pinned to a given CPU core and the total number of available threads is still governed by --threads or JULIA_NUM_THREADS.\n\nYou can pass both per=(core/thread) and minbatch=N options at the same time, e.g.\n\n@batch per=thread minbatch=2000 for i in Iter; ...; end\n@batch minbatch=5000 per=core   for i in Iter; ...; end\n\n\n\n\n\n","category":"macro"}]
}
